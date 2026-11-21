import Darwin
import Foundation

final class AgentControlServer {
    private let source: DispatchSourceRead

    init(
        address: AgentControlAddress,
        handle: @escaping @MainActor @Sendable (AgentControlRequest) -> AgentControlReply
    ) throws {
        try Self.prepareDirectory(address.directory)
        let ownerLock = try Self.lockAddress(address)
        var started = false
        defer {
            if !started { Darwin.close(ownerLock) }
        }

        let socket = try AgentControlSocket.openSocket()
        var bound = false
        defer {
            if !started {
                if bound { unlink(address.socket) }
                Darwin.close(socket)
            }
        }
        try AgentControlSocket.setNonblocking(socket, true)
        try Self.removeOldSocket(address.socket)
        guard try AgentControlSocket.withAddress(address.socket, { Darwin.bind(socket, $0, $1) }) == 0
        else { throw AgentControlSocket.posixError() }
        bound = true
        guard chmod(address.socket, 0o600) == 0, Darwin.listen(socket, 16) == 0
        else { throw AgentControlSocket.posixError() }

        let queue = DispatchQueue(label: "com.octoii.nosleep.agent-control")
        let workers = DispatchQueue.global(qos: .userInitiated)
        let available = DispatchSemaphore(value: 16)
        source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        source.setCancelHandler {
            Darwin.close(socket)
            unlink(address.socket)
            Darwin.close(ownerLock)
        }
        source.setEventHandler {
            for _ in 0..<16 {
                let client = Darwin.accept(socket, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    break
                }
                guard fcntl(client, F_SETFD, FD_CLOEXEC) == 0, available.wait(timeout: .now()) == .success else {
                    Darwin.close(client)
                    continue
                }
                workers.async {
                    let finish: @Sendable (AgentControlReply?) -> Void = { reply in
                        defer {
                            Darwin.close(client)
                            available.signal()
                        }
                        if let reply { try? AgentControlSocket.send(reply, on: client) }
                    }
                    do {
                        try AgentControlSocket.preparePeer(client)
                        let request = try AgentControlSocket.receive(AgentControlRequest.self, on: client)
                        Task { @MainActor in
                            let reply = handle(request)
                            workers.async { finish(reply) }
                        }
                    } catch is DecodingError {
                        finish(.failure(.invalidArguments))
                    } catch {
                        finish(nil)
                    }
                }
            }
        }
        started = true
        source.resume()
    }

    deinit { source.cancel() }

    private static func prepareDirectory(_ directory: URL) throws {
        let path = directory.path
        if mkdir(path, 0o700) != 0 && errno != EEXIST { throw AgentControlSocket.posixError() }
        var state = stat()
        guard lstat(path, &state) == 0, (state.st_mode & S_IFMT) == S_IFDIR,
              state.st_uid == geteuid(), (state.st_mode & 0o077) == 0
        else { throw AgentControlError.connectionFailed }
    }

    private static func lockAddress(_ address: AgentControlAddress) throws -> Int32 {
        let fd = Darwin.open(address.lock, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AgentControlSocket.posixError() }
        var state = stat()
        guard fstat(fd, &state) == 0, (state.st_mode & S_IFMT) == S_IFREG,
              state.st_uid == geteuid(), (state.st_mode & 0o077) == 0,
              flock(fd, LOCK_EX | LOCK_NB) == 0
        else {
            Darwin.close(fd)
            throw AgentControlError.connectionFailed
        }
        return fd
    }

    private static func removeOldSocket(_ path: String) throws {
        var state = stat()
        if lstat(path, &state) != 0 {
            if errno == ENOENT { return }
            throw AgentControlSocket.posixError()
        }
        guard (state.st_mode & S_IFMT) == S_IFSOCK, state.st_uid == geteuid(), unlink(path) == 0
        else { throw AgentControlError.connectionFailed }
    }
}
