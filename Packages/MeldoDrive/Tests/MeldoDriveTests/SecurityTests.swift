import Foundation
import MeldoKit
import MeldoState
import Testing
@testable import MeldoDrive

/// Regression tests for security fixes. Dummy data only.
@Suite("Security: Google Drive")
struct SecurityTests {
    /// A blob that opens with the key but isn't valid AppData is corrupt, not a newer
    /// Meldo: it's overwritten, so a peer can't wedge sync into a permanent "please update" state.
    @Test func aSealedButUndecodableFileIsOverwrittenNotTreatedAsNewer() async throws {
        let drive = MemoryDrive()
        let created = try BackupKey.create(password: "korrekt-pferd", rounds: 1_000)
        _ = try await DriveSync.storeKeyFile(created.file, in: drive)
        let keyID = DriveSync.keyID(created.file)
        let root = FileManager.default.temporaryDirectory.appending(path: "meldo-wedge-\(UUID().uuidString)")
        let scans = root.appending(path: "Scans")
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(url: root.appending(path: "data.json"))
        _ = try store.update { $0.subjects.append(Subject(name: "Mathe")) }
        let documents = DocumentFolder(
            locate: { ExamFiles.isSafe($0) ? scans.appending(path: $0) : nil },
            scans: { scans },
            isUploadable: { _ in true }
        )
        // A peer uploads bytes that open with the real key but aren't valid AppData JSON.
        let garbage = try SyncBox.seal(Data("nicht json".utf8), key: created.key, context: DriveSync.context(DriveSync.dataName))
        _ = try await drive.create(DriveSync.dataName, data: garbage)
        // Must not throw .newerVersion: the corrupt file is overwritten with this device's data.
        try await DriveSync.run(store: store, drive: drive, key: created.key, keyID: keyID, documents: documents)
        let files = await drive.contents(named: DriveSync.dataName)
        #expect(files.count == 1)
        let plain = try SyncBox.open(files[0], key: created.key, context: DriveSync.context(DriveSync.dataName))
        let decoded = try JSONDecoder.sync.decode(AppData.self, from: plain)
        #expect(decoded.subjects.contains { $0.name == "Mathe" })
    }
}
