import CommonCrypto
import CryptoKit
import Foundation
import MeldoKit
import MeldoState
import MeldoUI

/// One file in the app's hidden Google Drive folder.
nonisolated struct DriveFile: Sendable, Equatable {
    var id: String
    var name: String
    var created: Date
}

/// The app-data folder of the student's Google Drive (`GoogleDriveFiles`), or a
/// stand-in in tests. Meldo sees only this folder, never the student's other files.
nonisolated protocol DriveFiles: Sendable {
    func list() async throws -> [DriveFile]
    /// The file's bytes; throws `DriveSync.Problem.tooLarge` past `limit` without reading further.
    func read(_ id: String, limit: Int) async throws -> Data
    func create(_ name: String, data: Data) async throws -> DriveFile
    func update(_ id: String, data: Data) async throws
    func delete(_ id: String) async throws
}

/// The key that seals everything in Drive, wrapped with a key derived from the
/// student's backup password (like WhatsApp's encrypted backup). Only the wrapped
/// key is stored in Drive, so Google can't read the backup, and a forgotten
/// password can't be recovered.
nonisolated struct BackupKey: Codable, Equatable {
    static let fileName = "meldo-key"
    /// PBKDF2-HMAC-SHA256 rounds (OWASP 2023): about a second on a phone, once per device.
    static let defaultRounds = 600_000
    static let minimumPasswordLength = 8

    enum Problem: Error, Equatable {
        case wrongPassword, tooShort, damaged
        /// The unlocked key couldn't be stored in this device's Keychain.
        case notSaved
    }

    var version = 1
    var salt: Data
    var rounds: Int
    var wrapped: Data

    /// A new random data key and its wrapped form for `password`.
    static func create(password: String, rounds: Int = defaultRounds) throws -> (file: BackupKey, key: SymmetricKey) {
        guard password.count >= minimumPasswordLength else { throw Problem.tooShort }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Problem.damaged }
        let key = SymmetricKey(size: .bits256)
        let kek = try derive(password: password, salt: salt, rounds: rounds)
        let wrapped = try SyncBox.seal(key.withUnsafeBytes { Data($0) }, key: kek, context: context)
        return (BackupKey(salt: salt, rounds: rounds, wrapped: wrapped), key)
    }

    /// The data key, when `password` is the one it was created with. The rounds come
    /// from Drive: values that would make this hang or be trivially weak are refused.
    func unlock(password: String, minimumRounds: Int = defaultRounds) throws -> SymmetricKey {
        guard version == 1, (minimumRounds...3_000_000).contains(rounds), salt.count >= 16 else { throw Problem.damaged }
        let kek = try Self.derive(password: password, salt: salt, rounds: rounds)
        guard let plain = try? SyncBox.open(wrapped, key: kek, context: Self.context), plain.count == 32 else {
            throw Problem.wrongPassword
        }
        return SymmetricKey(data: plain)
    }

    private static let context = Data("MeldoBackupKey/v1".utf8)

    static func derive(password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        // The same password typed on another keyboard must give the same key.
        let secret = Data(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = secret.withUnsafeBytes { secretBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    secretBytes.baseAddress?.assumingMemoryBound(to: CChar.self), secret.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                    &derived, derived.count
                )
            }
        }
        guard status == kCCSuccess else { throw Problem.damaged }
        return SymmetricKey(data: derived)
    }
}

/// Where document PDFs live. The app uses `ExamFiles`; tests use a temporary folder
/// so they never touch the student's real scans.
nonisolated struct DocumentFolder: Sendable {
    var locate: @Sendable (String) -> URL?
    var scans: @Sendable () -> URL?
    /// Only regular files inside Meldo's folders are uploaded (no links someone placed there).
    var isUploadable: @Sendable (URL) -> Bool

    static let app = DocumentFolder(
        locate: { ExamFiles.locate($0) },
        scans: { ExamFiles.folder() },
        isUploadable: { url in
            (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true && ExamFiles.staysInside(url)
        }
    )
}

/// Google Drive sync and backup: an item-by-item merge
/// (`SyncMerge`), with every file sealed by `SyncBox` under the backup key.
nonisolated enum DriveSync {
    enum Problem: Error, Equatable {
        /// The backup was deleted, or another device started a new one with a new
        /// password: the key this device holds no longer belongs to it.
        case keyChanged
        /// A file in Drive is larger than any file Meldo writes; it is never downloaded.
        case tooLarge
        /// Another device saved with a newer Meldo; this one never overwrites that.
        case newerVersion
    }

    static let dataName = "meldo-data"
    /// Upper bounds for what is read from Drive (sealing adds 28 bytes).
    static let maxKeyBytes = 64 * 1024
    static let maxDataBytes = 50 * 1024 * 1024
    static let maxFileBytes = ExamFiles.maxImportBytes + 1024

    static func fileName(_ document: UUID) -> String { "meldo-file-\(document.uuidString)" }

    /// Identifies a key file. A device remembers it when it unlocks the backup and
    /// stops syncing when Drive's key file is a different one (or gone).
    static func keyID(_ key: BackupKey) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // The whole file (salt, rounds, wrapped key): no field can change unnoticed.
        let bytes = (try? encoder.encode(key)) ?? key.wrapped
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// The backup key file in Drive, or nil when this Google account has no Meldo backup yet.
    static func keyFile(in drive: some DriveFiles) async throws -> BackupKey? {
        try await keyFile(in: drive, files: try await drive.list())
    }

    private static func keyFile(in drive: some DriveFiles, files: [DriveFile]) async throws -> BackupKey? {
        guard let file = earliest(BackupKey.fileName, in: files) else { return nil }
        let data: Data
        do {
            data = try await drive.read(file.id, limit: maxKeyBytes)
        } catch Problem.tooLarge {
            throw BackupKey.Problem.damaged
        }
        guard let key = try? JSONDecoder().decode(BackupKey.self, from: data) else { throw BackupKey.Problem.damaged }
        return key
    }

    /// Stores a new key file. When another device stored one at the same moment, the
    /// first one wins and is returned instead.
    static func storeKeyFile(_ key: BackupKey, in drive: some DriveFiles) async throws -> BackupKey {
        let mine = try await drive.create(BackupKey.fileName, data: try JSONEncoder().encode(key))
        guard let winner = try await keyFile(in: drive), winner != key else { return key }
        // Lost the race: remove this device's key file so only one stays in Drive.
        try? await drive.delete(mine.id)
        return winner
    }

    /// Merges the Drive copy into `store`, uploads the result, then the documents.
    /// Throws `Problem.keyChanged` when Drive's backup isn't the one `keyID` names;
    /// stops between steps when the task is cancelled ("trennen").
    @concurrent
    static func run(store: LocalStore, drive: some DriveFiles, key: SymmetricKey, keyID: String,
                    documents: DocumentFolder = .app) async throws {
        let files = try await drive.list()
        // A deleted or replaced backup is never recreated under the old key. Network errors
        // pass through: only a missing, damaged or different key file means "changed".
        let current: BackupKey?
        do {
            current = try await keyFile(in: drive, files: files)
        } catch BackupKey.Problem.damaged {
            throw Problem.keyChanged
        }
        guard let current, Self.keyID(current) == keyID else { throw Problem.keyChanged }
        var merged = try store.load()
        let existing = earliest(dataName, in: files)
        if let existing, let theirs = try await remoteData(existing, in: drive, key: key) {
            merged = try store.update(stamping: false) { $0 = SyncMerge.merge(local: $0, remote: theirs) }
            // Nothing new here: no upload.
            if try canonical(merged) == canonical(theirs) {
                try await syncDocuments(of: merged, files: files, drive: drive, key: key, folder: documents)
                return
            }
        }
        try Task.checkCancellation()
        let sealed = try SyncBox.seal(JSONEncoder.sync.encode(merged), key: key, context: context(dataName))
        // Every device reads a larger file as damaged and replaces it with its own data, so one
        // this large is never uploaded: that would cost the other devices their changes.
        guard sealed.count <= maxDataBytes else { throw Problem.tooLarge }
        // shortcut: Drive has no conditional write, so two devices saving at the same moment can
        // overwrite each other's upload. Nothing is lost: each keeps its data and merges next time.
        if let existing {
            // Also repairs a meldo-data that couldn't be opened (other devices merge theirs back in).
            try await drive.update(existing.id, data: sealed)
        } else {
            _ = try await drive.create(dataName, data: sealed)
        }
        try await syncDocuments(of: merged, files: files, drive: drive, key: key, folder: documents)
    }

    /// The other devices' data, or nil when the file is damaged or planted (too large, or
    /// it doesn't open with the key): it is then overwritten with this device's data.
    /// Data that opens but this version can't read came from a newer Meldo: never overwritten.
    private static func remoteData(_ file: DriveFile, in drive: some DriveFiles, key: SymmetricKey) async throws -> AppData? {
        let sealed: Data
        do {
            sealed = try await drive.read(file.id, limit: maxDataBytes)
        } catch Problem.tooLarge {
            return nil
        }
        guard let plain = try? SyncBox.open(sealed, key: key, context: context(dataName)) else { return nil }
        // A blob that names a newer schema really is a newer Meldo: never overwrite it. One that
        // opens with our key but can't be decoded as current data — and names no newer schema — is
        // corrupt, not newer: return nil so it's overwritten instead of wedging sync for every device.
        if let probe = try? JSONDecoder.sync.decode(SchemaProbe.self, from: plain),
           probe.schemaVersion > AppData.currentSchemaVersion {
            throw Problem.newerVersion
        }
        guard let data = try? JSONDecoder.sync.decode(AppData.self, from: plain) else { return nil }
        return data
    }

    /// Just the schemaVersion of a sealed data blob, to tell a genuinely newer Meldo from a corrupt file.
    private struct SchemaProbe: Decodable { var schemaVersion = 1 }

    /// Uploads PDFs Drive doesn't have, downloads the ones this device misses, and
    /// removes the files of deleted documents. One damaged file never stops the others.
    // shortcut: a PDF is uploaded once and never compared again; edited scans need a content hash then.
    private static func syncDocuments(of data: AppData, files: [DriveFile], drive: some DriveFiles,
                                      key: SymmetricKey, folder: DocumentFolder) async throws {
        let manager = FileManager.default
        var byName: [String: DriveFile] = [:]
        for file in files {
            if let kept = byName[file.name], (kept.created, kept.id) < (file.created, file.id) { continue }
            byName[file.name] = file
        }
        for document in data.exams {
            try Task.checkCancellation()
            let name = fileName(document.id)
            let local = folder.locate(document.fileName)
            let hasLocal = local.map { manager.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
            switch (byName[name], hasLocal) {
            case let (remote?, false):
                // The synced name is lower-trust input: it must stay inside the scans folder.
                guard ExamFiles.isSafe(document.fileName),
                      let url = folder.scans()?.appending(path: document.fileName),
                      !manager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
                let pdf: Data
                do {
                    pdf = try SyncBox.open(try await drive.read(remote.id, limit: maxFileBytes), key: key, context: context(name))
                } catch Problem.tooLarge {
                    // Not a file Meldo wrote: remove it, a device that has the PDF uploads it again.
                    try? await drive.delete(remote.id)
                    continue
                } catch is CryptoKitError {
                    try? await drive.delete(remote.id)
                    continue
                }
                // A file added here while downloading (same name) is never replaced.
                guard !manager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
                // A name this device can't store (too long, or below a file) skips that document only;
                // the others and the cleanup below still run.
                do {
                    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try pdf.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                } catch {
                    continue
                }
            case (nil, true):
                guard let local, folder.isUploadable(local) else { continue }
                let sealed = try SyncBox.seal(Data(contentsOf: local), key: key, context: context(name))
                // Other devices delete a larger file as not Meldo's, so it would never arrive.
                guard sealed.count <= maxFileBytes else { continue }
                _ = try await drive.create(name, data: sealed)
            default:
                continue
            }
        }
        for key in data.sync.tombstones.keys where key.hasPrefix("exams:") {
            guard let id = UUID(uuidString: String(key.dropFirst("exams:".count))), let file = byName[fileName(id)] else { continue }
            try Task.checkCancellation()
            for duplicate in files where duplicate.name == file.name {
                try await drive.delete(duplicate.id)
            }
        }
    }

    /// The same data always gives the same bytes (sorted keys), for comparing.
    private static func canonical(_ data: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(data)
    }

    /// Two devices can create the same file at once; the oldest one counts.
    static func earliest(_ name: String, in files: [DriveFile]) -> DriveFile? {
        files.filter { $0.name == name }.min { ($0.created, $0.id) < ($1.created, $1.id) }
    }

    /// Binds a sealed file to its name, so one file's content can't stand in for another's.
    static func context(_ name: String) -> Data { Data("drive/\(name)".utf8) }
}

/// AES-256-GCM: a fresh nonce per message, tampering makes `open` fail. `context`
/// (the file it belongs to) is authenticated too, so it must match on `open`.
nonisolated enum SyncBox {
    static func seal(_ plain: Data, key: SymmetricKey, context: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key, authenticating: context).combined else {
            throw CryptoKitError.incorrectParameterSize
        }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey, context: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: context)
    }
}

extension JSONEncoder {
    nonisolated static var sync: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    nonisolated static var sync: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
