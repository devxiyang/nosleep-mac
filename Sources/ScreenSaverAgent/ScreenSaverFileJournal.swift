import Foundation

struct ScreenSaverFileJournal: ScreenSaverRecoveryJournal {
    private let directory = URL.applicationSupportDirectory.appending(path: ServiceIdentity.app, directoryHint: .isDirectory)
    private var file: URL { directory.appending(path: "screen-saver-recovery.json") }

    func load() throws -> ScreenSaverRecovery? {
        do {
            return try JSONDecoder().decode(ScreenSaverRecovery.self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func save(_ recovery: ScreenSaverRecovery) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(recovery).write(to: file, options: .atomic)
    }

    func clear() throws {
        do {
            try FileManager.default.removeItem(at: file)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}
