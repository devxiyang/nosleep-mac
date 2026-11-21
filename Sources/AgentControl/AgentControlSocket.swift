import Darwin
import Foundation

struct AgentControlAddress: Sendable {
    let directory: URL

    var socket: String { directory.appending(path: "mcp.sock").path }
    var lock: String { directory.appending(path: "mcp.lock").path }

    static func currentUser() throws -> Self {
        let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard size > 0 else { throw AgentControlError.connectionFailed }
        var directory = [CChar](repeating: 0, count: size)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &directory, size) == size,
              let path = directory.withUnsafeBufferPointer({ $0.baseAddress.flatMap(String.init(validatingCString:)) }),
              path.hasPrefix("/")
        else { throw AgentControlError.connectionFailed }
        let base = URL(fileURLWithPath: path, isDirectory: true)
        return Self(directory: base.appending(path: "nosleep", directoryHint: .isDirectory))
    }
}

enum AgentControlSocket {
    private static let timeoutSeconds = 3
    private static let maxMessageSize = 16 * 1024

    static func call(_ request: AgentControlRequest, at address: AgentControlAddress) throws -> AgentControlReply {
        let socket = try openSocket()
        defer { Darwin.close(socket) }
        try setNonblocking(socket, true)
        let result = try withAddress(address.socket) { Darwin.connect(socket, $0, $1) }
        if result != 0 {
            let error = errno
            if error == EINPROGRESS {
                try waitForConnection(socket)
            } else {
                throw connectionError(error)
            }
        }
        try preparePeer(socket)
        try send(request, on: socket)
        return try receive(AgentControlReply.self, on: socket)
    }

    static func openSocket() throws -> Int32 {
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { throw posixError() }
        guard fcntl(socket, F_SETFD, FD_CLOEXEC) == 0 else {
            let error = posixError()
            Darwin.close(socket)
            throw error
        }
        return socket
    }

    static func withAddress<Value>(
        _ path: String,
        _ operation: (UnsafePointer<sockaddr>, socklen_t) -> Value
    ) throws -> Value {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path), !bytes.contains(0)
        else { throw AgentControlError.connectionFailed }
        let size = MemoryLayout<sockaddr_un>.size
        address.sun_len = UInt8(size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { operation($0, socklen_t(size)) }
        }
    }

    static func setNonblocking(_ socket: Int32, _ enabled: Bool) throws {
        let flags = fcntl(socket, F_GETFL)
        guard flags >= 0,
              fcntl(socket, F_SETFL, enabled ? flags | O_NONBLOCK : flags & ~O_NONBLOCK) == 0
        else { throw posixError() }
    }

    static func preparePeer(_ socket: Int32) throws {
        var user: uid_t = 0
        var group: gid_t = 0
        guard getpeereid(socket, &user, &group) == 0, user == geteuid()
        else { throw AgentControlError.connectionFailed }
        guard fcntl(socket, F_SETFD, FD_CLOEXEC) == 0 else { throw posixError() }
        try setNonblocking(socket, false)
        var noSignal: Int32 = 1
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        guard setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0,
              setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0
        else { throw posixError() }
    }

    static func send<Value: Encodable>(_ value: Value, on socket: Int32) throws {
        var message = try JSONEncoder().encode(value)
        guard message.count <= maxMessageSize else { throw AgentControlError.connectionFailed }
        message.append(0x0A)
        try message.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { throw AgentControlError.connectionFailed }
            var written = 0
            while written < buffer.count {
                let count = Darwin.send(socket, base.advanced(by: written), buffer.count - written, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AgentControlError.connectionFailed }
                written += count
            }
        }
    }

    static func receive<Value: Decodable>(_ type: Value.Type, on socket: Int32) throws -> Value {
        var message = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            let count = buffer.withUnsafeMutableBytes { Darwin.recv(socket, $0.baseAddress, $0.count, 0) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw AgentControlError.connectionFailed }
            let chunk = buffer.prefix(count)
            let payload = chunk.prefix { $0 != 0x0A }
            guard message.count + payload.count <= maxMessageSize else { throw AgentControlError.invalidArguments }
            message.append(contentsOf: payload)
            if payload.count < chunk.count {
                return try JSONDecoder().decode(type, from: message)
            }
        }
        throw AgentControlError.connectionFailed
    }

    static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private static func connectionError(_ code: Int32) -> AgentControlError {
        code == ENOENT || code == ECONNREFUSED ? .appNotRunning : .connectionFailed
    }

    private static func waitForConnection(_ socket: Int32) throws {
        var event = pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)
        guard poll(&event, 1, Int32(timeoutSeconds * 1000)) > 0 else { throw AgentControlError.connectionFailed }
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &size) == 0
        else { throw AgentControlError.connectionFailed }
        if error != 0 { throw connectionError(error) }
    }
}
