import Foundation

/// Device-local persistence as one JSON document, written atomically and
/// protected by iOS data protection. Small by design: a school year of data
/// is well under a megabyte.
///
/// The file lives in the App Group container so the app, its widgets and the
/// Melden control share it. All writes go through `update`, which reads the
/// current file under an `NSFileCoordinator` lock and applies the change, so
/// a Meldung logged from the Lock Screen is never overwritten by the app.
public nonisolated struct LocalStore: Sendable {
    public enum LoadError: Error, Sendable {
        case unreadable(underlying: any Error, backup: URL?)
        case newerSchema(Int)
    }

    public let url: URL
    /// `false` when the App Group is unavailable (some sideloading tools strip it);
    /// the app then keeps its data privately and widgets show a hint instead.
    public let isShared: Bool

    public init(url: URL, isShared: Bool = false) {
        self.url = url
        self.isShared = isShared
    }

    /// The shared store, migrating the file from the app's private container
    /// the first time the App Group is available.
    public static func standard() throws -> LocalStore {
        let privateURL = try privateFolder().appending(path: "data.json")
        guard let group = AppGroup.containerURL else {
            return LocalStore(url: privateURL)
        }
        let folder = group.appending(path: "MeldePlanner", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sharedURL = folder.appending(path: "data.json")
        let fm = FileManager.default
        if !fm.fileExists(atPath: sharedURL.path(percentEncoded: false)),
           fm.fileExists(atPath: privateURL.path(percentEncoded: false)) {
            try fm.copyItem(at: privateURL, to: sharedURL)
            try? fm.removeItem(at: privateURL)
        }
        removeLeftovers(in: [privateURL.deletingLastPathComponent(), folder])
        return LocalStore(url: sharedURL, isShared: true)
    }

    /// For widgets and intents: the shared store only, `nil` without the App Group.
    public static func sharedIfAvailable() -> LocalStore? {
        guard let group = AppGroup.containerURL else { return nil }
        return LocalStore(url: group.appending(path: "MeldePlanner/data.json"), isShared: true)
    }

    /// Deleted entries must not live on in old copies (privacy policy): the pre-App-Group
    /// copy goes at once, copies of an unreadable file after 30 days.
    public static func removeLeftovers(in folders: [URL], now: Date = Date()) {
        let fm = FileManager.default
        for folder in folders {
            try? fm.removeItem(at: folder.appending(path: "data-before-app-group.json"))
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix("data-unreadable-") {
                let stamp = Double(file.deletingPathExtension().lastPathComponent.dropFirst("data-unreadable-".count)) ?? 0
                if now.timeIntervalSince1970 - stamp > 30 * 24 * 3600 { try? fm.removeItem(at: file) }
            }
        }
    }

    private static func privateFolder() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = base.appending(path: "MeldePlanner", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public func load() throws(LoadError) -> AppData {
        var result: Result<AppData, LoadError> = .success(AppData())
        coordinate(writing: false) { url in result = Self.read(url) }
        return try result.get()
    }

    /// Reads the latest file, applies `change` and writes it back, all under
    /// one coordinated write so concurrent writers (app, widget) serialize.
    /// What changed is stamped for sync; merging data that came from
    /// Sync passes `stamping: false`, since those items keep their own times.
    @discardableResult
    public func update(stamping: Bool = true, _ change: (inout AppData) -> Void) throws -> AppData {
        var outcome: Result<AppData, any Error> = .failure(CocoaError(.fileWriteUnknown))
        coordinate(writing: true) { url in
            do {
                var data: AppData
                switch Self.read(url) {
                case .success(let current): data = current
                // Corrupt and safely backed up by `read`: start fresh rather than blocking every save.
                // Without a backup (e.g. the file is locked before the first unlock) nothing is overwritten.
                case .failure(.unreadable(_, backup: .some)): data = AppData()
                // Never overwrite data written by a newer app version.
                case .failure(let error): throw error
                }
                let before = data
                change(&data)
                if stamping { SyncMerge.record(from: before, to: &data, at: Date()) }
                try Self.write(data, to: url)
                outcome = .success(data)
            } catch {
                outcome = .failure(error)
            }
        }
        return try outcome.get()
    }

    /// Overwrites the file. Only for tests and recovery; normal code uses `update`.
    public func save(_ appData: AppData) throws {
        var outcome: Result<Void, any Error> = .success(())
        coordinate(writing: true) { url in
            outcome = Result { try Self.write(appData, to: url) }
        }
        try outcome.get()
    }

    private func coordinate(writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error, byAccessor: body)
        }
    }

    private static func read(_ url: URL) -> Result<AppData, LoadError> {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return .success(AppData())
        }
        // A file that can't be read (I/O, data protection) is not corrupt: report it without a backup.
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            return .failure(.unreadable(underlying: error, backup: nil))
        }
        do {
            var decoded = try decoder().decode(AppData.self, from: raw)
            if decoded.schemaVersion > AppData.currentSchemaVersion {
                return .failure(.newerSchema(decoded.schemaVersion))
            }
            // Older files are migrated in memory; the next write stores the current version.
            decoded.schemaVersion = AppData.currentSchemaVersion
            return .success(decoded)
        } catch {
            // Keep the unreadable file instead of overwriting the student's data.
            return .failure(.unreadable(underlying: error, backup: backupCorruptFile(url)))
        }
    }

    private static func write(_ appData: AppData, to url: URL) throws {
        let data = try encoder().encode(appData)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func backupCorruptFile(_ url: URL) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appending(path: "data-unreadable-\(stamp).json")
        return (try? FileManager.default.copyItem(at: url, to: backup)) != nil ? backup : nil
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
