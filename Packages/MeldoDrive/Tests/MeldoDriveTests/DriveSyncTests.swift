import CryptoKit
import Foundation
import MeldoKit
import MeldoState
import Testing
@testable import MeldoDrive

/// Stand-in for the Google Drive app-data folder, kept in memory (tests only).
actor MemoryDrive: DriveFiles {
    private(set) var files: [String: (name: String, data: Data, created: Date)] = [:]
    private(set) var writes = 0
    private(set) var reads = 0
    /// Simulates the network dropping during reads.
    var offline = false

    func setOffline(_ value: Bool) { offline = value }
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    func list() async throws -> [DriveFile] {
        files.map { DriveFile(id: $0.key, name: $0.value.name, created: $0.value.created) }
    }

    func read(_ id: String, limit: Int) async throws -> Data {
        guard !offline, let file = files[id] else { throw GoogleClient.Failure.network }
        guard file.data.count <= limit else { throw DriveSync.Problem.tooLarge }
        reads += 1
        return file.data
    }

    /// Replaces a file's content, the way anyone holding the Google account could.
    func overwrite(named name: String, with data: Data) {
        for (id, file) in files where file.name == name { files[id] = (file.name, data, file.created) }
    }

    func create(_ name: String, data: Data) async throws -> DriveFile {
        clock.addTimeInterval(1)
        writes += 1
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        files[id] = (name, data, clock)
        return DriveFile(id: id, name: name, created: clock)
    }

    func update(_ id: String, data: Data) async throws {
        guard let file = files[id] else { throw GoogleClient.Failure.network }
        writes += 1
        files[id] = (file.name, data, file.created)
    }

    func delete(_ id: String) async throws {
        files[id] = nil
    }

    func contents(named name: String) -> [Data] {
        files.values.filter { $0.name == name }.map(\.data)
    }
}

@Suite("Google Drive sync")
struct DriveSyncTests {
    /// A device: its own data file and document folder in a temporary directory.
    struct Device {
        let store: LocalStore
        let folder: URL
        var documents: DocumentFolder {
            let folder = folder
            return DocumentFolder(
                locate: { ExamFiles.isSafe($0) ? folder.appending(path: $0) : nil },
                scans: { folder },
                isUploadable: { _ in true }
            )
        }

        init() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "drive-\(UUID().uuidString)")
            folder = root.appending(path: "Scans")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            store = LocalStore(url: root.appending(path: "data.json"))
        }
    }

    /// A Drive with a backup key file, and the key and key ID a device unlocked from it.
    func backup() async throws -> (drive: MemoryDrive, key: SymmetricKey, keyID: String) {
        let drive = MemoryDrive()
        let created = try BackupKey.create(password: "korrekt-pferd", rounds: 1_000)
        _ = try await DriveSync.storeKeyFile(created.file, in: drive)
        return (drive, created.key, DriveSync.keyID(created.file))
    }

    @Test func passwordOpensOnlyItsOwnBackup() throws {
        let created = try BackupKey.create(password: "korrekt-pferd", rounds: 1_000)
        let opened = try created.file.unlock(password: "korrekt-pferd", minimumRounds: 1_000)
        #expect(opened.withUnsafeBytes { Data($0) } == created.key.withUnsafeBytes { Data($0) })
        #expect(throws: BackupKey.Problem.wrongPassword) { try created.file.unlock(password: "falsch-pferd", minimumRounds: 1_000) }
        #expect(throws: BackupKey.Problem.tooShort) { try BackupKey.create(password: "kurz", rounds: 1_000) }
        // A key file from Drive asking for few rounds (or absurdly many) is refused in the app.
        #expect(throws: BackupKey.Problem.damaged) { try created.file.unlock(password: "korrekt-pferd") }
        var huge = created.file
        huge.rounds = 2_000_000_000
        #expect(throws: BackupKey.Problem.damaged) { try huge.unlock(password: "korrekt-pferd", minimumRounds: 1_000) }
    }

    @Test func theSamePasswordTypedDifferentlyGivesTheSameKey() throws {
        let salt = Data(repeating: 7, count: 16)
        // "ü" as one character and as "u" + combining diaeresis.
        let composed = try BackupKey.derive(password: "Schl\u{00FC}ssel", salt: salt, rounds: 1_000)
        let decomposed = try BackupKey.derive(password: "Schlu\u{0308}ssel", salt: salt, rounds: 1_000)
        #expect(composed == decomposed)
    }

    @Test func twoDevicesShareTheirChanges() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device(), ipad = try Device()
        _ = try phone.store.update { $0.subjects.append(Subject(name: "Mathe")) }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        try await DriveSync.run(store: ipad.store, drive: drive, key: key, keyID: keyID, documents: ipad.documents)
        #expect(try ipad.store.load().subjects.map(\.name) == ["Mathe"])

        _ = try ipad.store.update { $0.subjects.append(Subject(name: "Bio")) }
        try await DriveSync.run(store: ipad.store, drive: drive, key: key, keyID: keyID, documents: ipad.documents)
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        #expect(try phone.store.load().subjects.map(\.name) == ["Mathe", "Bio"])
        // One data file, not one per device or sync.
        #expect(await drive.contents(named: DriveSync.dataName).count == 1)
    }

    @Test func driveOnlyHoldsCiphertext() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device()
        _ = try phone.store.update { $0.subjects.append(Subject(name: "Geheimfach")) }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        let stored = try #require(await drive.contents(named: DriveSync.dataName).first)
        #expect(stored.range(of: Data("Geheimfach".utf8)) == nil)
        // A key from another backup is refused before anything is read or written.
        let stranger = try Device()
        let other = try BackupKey.create(password: "fremdes-passwort", rounds: 1_000)
        await #expect(throws: DriveSync.Problem.keyChanged) {
            try await DriveSync.run(store: stranger.store, drive: drive, key: other.key, keyID: DriveSync.keyID(other.file),
                                    documents: stranger.documents)
        }
        #expect(try stranger.store.load().subjects.isEmpty)
        #expect(await drive.contents(named: DriveSync.dataName).first == stored)
    }

    @Test func documentsTravelAndDeletionsFollow() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device(), ipad = try Device()
        let exam = ExamDocument(title: "1. Klausur", date: .now, fileName: "Mathe/Exams/1. Klausur.pdf", pageCount: 1)
        let pdf = Data("%PDF-1.7 Klausur".utf8)
        try FileManager.default.createDirectory(at: phone.folder.appending(path: "Mathe/Exams"), withIntermediateDirectories: true)
        try pdf.write(to: phone.folder.appending(path: exam.fileName))
        _ = try phone.store.update { $0.exams.append(exam) }

        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        #expect(await drive.contents(named: DriveSync.fileName(exam.id)).first?.range(of: Data("Klausur".utf8)) == nil)
        try await DriveSync.run(store: ipad.store, drive: drive, key: key, keyID: keyID, documents: ipad.documents)
        #expect(try Data(contentsOf: ipad.folder.appending(path: exam.fileName)) == pdf)

        // Deleted on the iPad: the PDF leaves Drive too.
        _ = try ipad.store.update { $0.exams.removeAll() }
        try await DriveSync.run(store: ipad.store, drive: drive, key: key, keyID: keyID, documents: ipad.documents)
        #expect(await drive.contents(named: DriveSync.fileName(exam.id)).isEmpty)
    }

    /// A document this device can't store under its name (here below a file) is skipped; the rest still syncs.
    @Test func aDocumentThatCantBeStoredDoesNotStopTheOthers() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device(), ipad = try Device()
        let blocked = ExamDocument(title: "a", date: .now, fileName: "a.pdf/c.pdf", pageCount: 1)
        let ok = ExamDocument(title: "ok", date: .now, fileName: "Other/ok.pdf", pageCount: 1)
        for exam in [blocked, ok] {
            let url = phone.folder.appending(path: exam.fileName)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("%PDF \(exam.title)".utf8).write(to: url)
            _ = try phone.store.update { $0.exams.append(exam) }
        }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)

        // On the iPad "a.pdf" is a file, so nothing can be stored below it.
        try Data("%PDF other".utf8).write(to: ipad.folder.appending(path: "a.pdf"))
        try await DriveSync.run(store: ipad.store, drive: drive, key: key, keyID: keyID, documents: ipad.documents)
        #expect(try Data(contentsOf: ipad.folder.appending(path: ok.fileName)) == Data("%PDF ok".utf8))
    }

    @Test func aSyncedFileNameCantLeaveTheScansFolder() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device(), ipad = try Device()
        let exam = ExamDocument(title: "x", date: .now, fileName: "Scan.pdf", pageCount: 1)
        try Data("%PDF".utf8).write(to: phone.folder.appending(path: exam.fileName))
        _ = try phone.store.update { $0.exams.append(exam) }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        // Another device renames the document to point outside the folder.
        _ = try phone.store.update { $0.exams[0].fileName = "../../escaped.pdf" }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        try await DriveSync.run(store: ipad.store, drive: drive, key: key, keyID: keyID, documents: ipad.documents)
        let outside = ipad.folder.deletingLastPathComponent().deletingLastPathComponent().appending(path: "escaped.pdf")
        #expect(!FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
    }

    @Test func aDeletedBackupIsNeverRecreatedUnderTheOldKey() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device(), ipad = try Device()
        _ = try phone.store.update { $0.subjects.append(Subject(name: "Mathe")) }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        // "Backup löschen" on the iPad: every file goes.
        for file in try await drive.list() { try await drive.delete(file.id) }
        await #expect(throws: DriveSync.Problem.keyChanged) {
            try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        }
        #expect(try await drive.list().isEmpty)
        // A new backup with a new password: the phone stops instead of writing under its old key.
        let fresh = try BackupKey.create(password: "neues-passwort", rounds: 1_000)
        _ = try await DriveSync.storeKeyFile(fresh.file, in: drive)
        await #expect(throws: DriveSync.Problem.keyChanged) {
            try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        }
        #expect(await drive.contents(named: DriveSync.dataName).isEmpty)
        _ = ipad
    }

    @Test func aDamagedDataFileIsRepairedNotFatal() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device()
        _ = try phone.store.update { $0.subjects.append(Subject(name: "Mathe")) }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        await drive.overwrite(named: DriveSync.dataName, with: Data(repeating: 7, count: 64))
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        // The phone's data went back up and opens again.
        let ipad = try Device()
        try await DriveSync.run(store: ipad.store, drive: drive, key: key, keyID: keyID, documents: ipad.documents)
        #expect(try ipad.store.load().subjects.map(\.name) == ["Mathe"])
    }

    @Test func oversizedAndDamagedFilesAreNotDownloaded() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device(), ipad = try Device()
        let big = ExamDocument(title: "Groß", date: .now, fileName: "Groß.pdf", pageCount: 1)
        let broken = ExamDocument(title: "Kaputt", date: .now, fileName: "Kaputt.pdf", pageCount: 1)
        let good = ExamDocument(title: "Gut", date: .now, fileName: "Gut.pdf", pageCount: 1)
        for exam in [big, broken, good] { try Data("%PDF".utf8).write(to: phone.folder.appending(path: exam.fileName)) }
        _ = try phone.store.update { $0.exams = [big, broken, good] }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        await drive.overwrite(named: DriveSync.fileName(big.id), with: Data(count: DriveSync.maxFileBytes + 1))
        await drive.overwrite(named: DriveSync.fileName(broken.id), with: Data(repeating: 1, count: 40))
        try await DriveSync.run(store: ipad.store, drive: drive, key: key, keyID: keyID, documents: ipad.documents)
        // The good PDF still arrives; the planted files are removed instead of stopping sync.
        #expect(FileManager.default.fileExists(atPath: ipad.folder.appending(path: good.fileName).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: ipad.folder.appending(path: big.fileName).path(percentEncoded: false)))
        #expect(await drive.contents(named: DriveSync.fileName(big.id)).isEmpty)
        #expect(await drive.contents(named: DriveSync.fileName(broken.id)).isEmpty)
    }

    @Test func aNetworkDropIsNotAChangedBackup() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device()
        await drive.setOffline(true)
        await #expect(throws: GoogleClient.Failure.network) {
            try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        }
    }

    @Test func dataFromANewerMeldoIsNeverOverwritten() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device()
        var newer = AppData()
        newer.schemaVersion = AppData.currentSchemaVersion + 1
        let sealed = try SyncBox.seal(JSONEncoder.sync.encode(newer), key: key, context: DriveSync.context(DriveSync.dataName))
        _ = try await drive.create(DriveSync.dataName, data: sealed)
        await #expect(throws: DriveSync.Problem.newerVersion) {
            try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        }
        #expect(await drive.contents(named: DriveSync.dataName) == [sealed])
    }

    @Test func theOldestOfTwoKeyFilesWins() async throws {
        let drive = MemoryDrive()
        let first = try BackupKey.create(password: "erstes-passwort", rounds: 1_000)
        let second = try BackupKey.create(password: "zweites-passwort", rounds: 1_000)
        _ = try await DriveSync.storeKeyFile(first.file, in: drive)
        // A second device stored its key at the same moment: it gets the first one back,
        // and its own key file doesn't stay behind.
        #expect(try await DriveSync.storeKeyFile(second.file, in: drive) == first.file)
        #expect(await drive.contents(named: BackupKey.fileName).count == 1)
    }

    @Test func aSyncWithoutChangesUploadsNothing() async throws {
        let (drive, key, keyID) = try await backup()
        let phone = try Device()
        _ = try phone.store.update { $0.subjects.append(Subject(name: "Mathe")) }
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        let writes = await drive.writes
        try await DriveSync.run(store: phone.store, drive: drive, key: key, keyID: keyID, documents: phone.documents)
        #expect(await drive.writes == writes)
    }

    @Test func tokensOnlyGoToGoogleItself() {
        func request(_ url: String) -> URLRequest {
            var r = URLRequest(url: URL(string: url)!)
            r.setValue("Bearer t", forHTTPHeaderField: "Authorization")
            return r
        }
        let api = request("https://www.googleapis.com/drive/v3/files/abc?alt=media")
        #expect(GoogleRedirectGuard.follow(from: api, to: request("https://www.googleapis.com/x"))?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        // Google's content host gets the download, without the token.
        let moved = GoogleRedirectGuard.follow(from: api, to: request("https://doc-0s-1.googleusercontent.com/x"))
        #expect(moved != nil && moved?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(GoogleRedirectGuard.follow(from: api, to: request("https://evil.example.com/x")) == nil)
        #expect(GoogleRedirectGuard.follow(from: api, to: request("https://googleusercontent.com.evil.com/x")) == nil)
        #expect(GoogleRedirectGuard.follow(from: api, to: request("http://doc.googleusercontent.com/x")) == nil)
    }

    @Test func driveIDsCantChangeTheRequestPath() {
        #expect(GoogleDriveFiles.isID("1AbC-_x9"))
        #expect(!GoogleDriveFiles.isID("../files"))
        #expect(!GoogleDriveFiles.isID("a?alt=media"))
        #expect(!GoogleDriveFiles.isID(""))
    }
}

@Suite("Sync encryption")
struct SyncBoxTests {
    @Test func sealedDataOpensOnlyWithTheSameKey() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("Mathe 2-".utf8)
        let sealed = try SyncBox.seal(plain, key: key, context: Data("MeldoData/data".utf8))
        #expect(sealed != plain)
        #expect(try SyncBox.open(sealed, key: key, context: Data("MeldoData/data".utf8)) == plain)
        // Another record's ciphertext doesn't open as this one.
        #expect(throws: (any Error).self) { try SyncBox.open(sealed, key: key, context: Data("MeldoFile/x".utf8)) }
        #expect(throws: (any Error).self) { try SyncBox.open(sealed, key: SymmetricKey(size: .bits256), context: Data("MeldoData/data".utf8)) }
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01
        #expect(throws: (any Error).self) { try SyncBox.open(tampered, key: key, context: Data("MeldoData/data".utf8)) }
    }
}
