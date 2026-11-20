import Darwin
import Foundation

struct FileRecoveryJournal: PowerRecoveryJournal {
    private let directory = URL(
        fileURLWithPath: "/private/var/db/" + ServiceIdentity.helper,
        isDirectory: true
    )

    private var file: URL { directory.appending(path: "power-recovery.json") }

    func load() throws -> PowerRecovery? {
        try prepareDirectory()
        do {
            return try JSONDecoder().decode(PowerRecovery.self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func save(_ recovery: PowerRecovery) throws {
        try prepareDirectory()
        try JSONEncoder().encode(recovery).write(to: file, options: .atomic)
    }

    func clear() throws {
        do {
            try FileManager.default.removeItem(at: file)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    private func prepareDirectory() throws {
        let path = directory.path
        if mkdir(path, 0o700) != 0 && errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var info = stat()
        guard lstat(path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == 0,
              (info.st_mode & 0o077) == 0
        else {
            throw POSIXError(.EPERM)
        }
    }
}
