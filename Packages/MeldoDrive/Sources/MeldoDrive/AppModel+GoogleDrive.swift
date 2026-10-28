import CryptoKit
import Foundation
import MeldoState
import MeldoUI
import Observation
import MeldoKit

/// Google Drive status on this device (per device, never synced).
@Observable
final class DriveSession {
    var state = AppModel.DriveState.off
    var isSyncing = false
    /// The connected Google account (not secret) and the last backup.
    var account = UserDefaults.standard.string(forKey: AppModel.driveAccountKey)
    var lastSync = UserDefaults.standard.object(forKey: AppModel.driveLastSyncKey) as? Date
    var problem: String?
    var syncTask: Task<Void, Never>?
    /// The Drive sync running now; "trennen" cancels it between steps.
    @ObservationIgnored var runTask: Task<Void, any Error>?
    /// Bumped by "Google Drive trennen": work started earlier stops writing.
    @ObservationIgnored var generation = 0
    @ObservationIgnored var access: GoogleClient.Tokens?
}

/// Google Drive sync and backup for this device. The Google sign-in and
/// the unlocked backup key stay in this device's Keychain; the backup in Drive is
/// sealed with a key only the student's backup password opens.
extension AppModel {
    enum DriveState: Equatable {
        /// Not signed in to Google.
        case off
        /// Signed in; the backup password is still needed on this device.
        case needsPassword
        case on
    }

    var driveSession: DriveSession { moduleState(DriveSession.init) }
    var driveState: DriveState { get { driveSession.state } set { driveSession.state = newValue } }
    var isSyncingWithDrive: Bool { get { driveSession.isSyncing } set { driveSession.isSyncing = newValue } }
    var driveAccount: String? { get { driveSession.account } set { driveSession.account = newValue } }
    var lastDriveSync: Date? { get { driveSession.lastSync } set { driveSession.lastSync = newValue } }
    var driveProblem: String? { get { driveSession.problem } set { driveSession.problem = newValue } }
    var driveSyncTask: Task<Void, Never>? { get { driveSession.syncTask } set { driveSession.syncTask = newValue } }
    var driveRunTask: Task<Void, any Error>? { get { driveSession.runTask } set { driveSession.runTask = newValue } }
    var driveGeneration: Int { get { driveSession.generation } set { driveSession.generation = newValue } }
    var driveAccess: GoogleClient.Tokens? { get { driveSession.access } set { driveSession.access = newValue } }

    /// Reads this device's Drive status and backs up after every change.
    func installDrive() {
        if hasReadableStore { driveState = Self.storedDriveState() }
        onChange { [weak self] in self?.scheduleDriveSync() }
    }

    /// The Drive sign-in and key are per install: after a reinstall, sign in again.
    static let perInstallSecrets = [driveTokenAccount, driveKeyAccount]

    static let driveTokenAccount = "google-drive"
    static let driveKeyAccount = "google-drive-key"
    static let driveAccountKey = "gdrive.account"
    static let driveLastSyncKey = "gdrive.lastSync"

    static func storedDriveState() -> DriveState {
        guard Keychain.read(account: driveTokenAccount) != nil else { return .off }
        return storedDriveKey() == nil ? .needsPassword : .on
    }

    /// The unlocked data key and the ID of the key file it came from ("key:id" in the Keychain).
    private static func storedDriveKey() -> (key: SymmetricKey, keyID: String)? {
        guard let stored = Keychain.read(account: driveKeyAccount) else { return nil }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let data = Data(base64Encoded: parts[0]), data.count == 32, !parts[1].isEmpty else { return nil }
        return (SymmetricKey(data: data), parts[1])
    }

    /// Finishes the Google sign-in with the code from Google's redirect.
    func connectGoogle(code: String, verifier: String) async throws(GoogleClient.Failure) {
        let generation = driveGeneration
        let tokens = try await GoogleClient().redeem(code: code, verifier: verifier)
        guard generation == driveGeneration else { throw .cancelled }
        guard !tokens.refresh.isEmpty else { throw .denied("") }
        // A key left from an earlier sign-in never carries over to this account.
        Keychain.delete(account: Self.driveKeyAccount)
        guard Keychain.save(tokens.refresh, account: Self.driveTokenAccount) else { throw .denied("") }
        driveAccess = tokens
        driveProblem = nil
        driveState = .needsPassword
        driveAccount = await GoogleClient().accountEmail(access: tokens.access)
        UserDefaults.standard.set(driveAccount, forKey: Self.driveAccountKey)
    }

    /// Whether this Google account already has a Meldo backup (then the password opens it;
    /// otherwise the password creates it).
    func driveHasBackup() async throws -> Bool {
        try await DriveSync.keyFile(in: drive()) != nil
    }

    /// Opens the existing backup with `password`, or creates the backup key with it.
    /// `creating` is what the screen showed: a backup that appeared or vanished meanwhile
    /// throws `DriveSync.Problem.keyChanged`, so one unconfirmed password never starts a new one.
    /// Throws `BackupKey.Problem.wrongPassword` or `.tooShort`.
    func unlockDrive(password: String, creating: Bool) async throws {
        let generation = driveGeneration
        let files = try await drive()
        let key: SymmetricKey
        let keyFile: BackupKey
        let existing = try await DriveSync.keyFile(in: files)
        guard (existing == nil) == creating else { throw DriveSync.Problem.keyChanged }
        if let file = existing {
            key = try await Task.detached { try file.unlock(password: password) }.value
            keyFile = file
        } else {
            let created = try await Task.detached { try BackupKey.create(password: password) }.value
            keyFile = try await DriveSync.storeKeyFile(created.file, in: files)
            // Another device created the backup at the same moment: its key counts.
            key = keyFile == created.file ? created.key : try await Task.detached { try keyFile.unlock(password: password) }.value
        }
        guard generation == driveGeneration else { throw GoogleClient.Failure.cancelled }
        let stored = key.withUnsafeBytes { Data($0) }.base64EncodedString() + ":" + DriveSync.keyID(keyFile)
        guard Keychain.save(stored, account: Self.driveKeyAccount) else { throw BackupKey.Problem.notSaved }
        driveProblem = nil
        driveState = .on
        await syncWithGoogleDrive()
    }

    /// After a change: wait a moment so a burst of edits goes up in one backup.
    func scheduleDriveSync() {
        guard driveState == .on, store != nil else { return }
        driveSyncTask?.cancel()
        driveSyncTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await syncWithGoogleDrive()
        }
    }

    /// Merges what other devices saved, uploads this device's changes and documents.
    func syncWithGoogleDrive() async {
        // Launched before the first unlock, the Keychain looked empty: look again.
        if driveState == .off { driveState = Self.storedDriveState() }
        guard driveState == .on, let store, !isSyncingWithDrive, let stored = Self.storedDriveKey() else { return }
        isSyncingWithDrive = true
        defer { isSyncingWithDrive = false }
        let before = data
        let generation = driveGeneration
        let run = Task {
            let files = try await drive()
            try await DriveSync.run(store: store, drive: files, key: stored.key, keyID: stored.keyID)
        }
        driveRunTask = run
        defer { driveRunTask = nil }
        let result = await run.result
        // The merge may be on disk even when a later step failed: this device follows it
        // (forgotten secrets, removed PDFs, reminders) either way.
        applyMerged(since: before)
        guard generation == driveGeneration else { return }
        switch result {
        case .success:
            lastDriveSync = currentDate
            UserDefaults.standard.set(lastDriveSync, forKey: Self.driveLastSyncKey)
            driveProblem = nil
        case .failure(DriveSync.Problem.keyChanged):
            // Deleted, or restarted with a new password on another device: never write
            // under the old key again. The password opens the new backup.
            Keychain.delete(account: Self.driveKeyAccount)
            driveState = .needsPassword
            driveProblem = L("Das Backup wurde auf einem anderen Gerät gelöscht oder neu angelegt. Gib das Backup-Passwort ein.")
        case .failure(DriveSync.Problem.newerVersion):
            driveProblem = L("Ein anderes Gerät nutzt eine neuere Meldo-Version. Aktualisiere Meldo, damit es weiter sichert.")
        case .failure(GoogleClient.Failure.expired):
            driveProblem = L("Deine Google-Anmeldung ist abgelaufen. Melde dich erneut an.")
        case .failure:
            driveProblem = L("Google Drive ist gerade nicht erreichbar. Meldo versucht es später noch einmal.")
        }
    }

    /// Forgets the Google sign-in and the backup key on this device. The backup in
    /// Drive stays, for other devices and a later restore.
    func disconnectGoogle() {
        driveGeneration += 1
        driveSyncTask?.cancel()
        driveRunTask?.cancel()
        if let token = Keychain.read(account: Self.driveTokenAccount) {
            Task.detached { await GoogleClient().revoke(token) }
        }
        Keychain.delete(account: Self.driveTokenAccount)
        Keychain.delete(account: Self.driveKeyAccount)
        driveAccess = nil
        driveProblem = nil
        lastDriveSync = nil
        driveAccount = nil
        UserDefaults.standard.removeObject(forKey: Self.driveLastSyncKey)
        UserDefaults.standard.removeObject(forKey: Self.driveAccountKey)
        driveState = .off
    }

    /// Deletes Meldo's backup from Google Drive (all devices lose it), then disconnects.
    /// Also the way out of a forgotten backup password.
    func deleteDriveBackup() async throws {
        // Stop this device's own syncs first, so none recreates a file after the sweep.
        driveSyncTask?.cancel()
        driveRunTask?.cancel()
        _ = await driveRunTask?.result
        Keychain.delete(account: Self.driveKeyAccount)
        driveState = .needsPassword
        let files = try await drive()
        // The key file last: if this fails halfway, the backup still has its key.
        let all = try await files.list().sorted { ($0.name == BackupKey.fileName ? 1 : 0) < ($1.name == BackupKey.fileName ? 1 : 0) }
        for file in all {
            try await files.delete(file.id)
        }
        disconnectGoogle()
    }

    /// Drive with a fresh access token, renewed from the stored sign-in when needed.
    private func drive() async throws -> GoogleDriveFiles {
        if let access = driveAccess, access.expires > Date() { return GoogleDriveFiles(access: access.access) }
        guard let refresh = Keychain.read(account: Self.driveTokenAccount) else { throw GoogleClient.Failure.expired }
        let generation = driveGeneration
        let tokens = try await GoogleClient().refresh(refresh)
        // "Trennen" while Google answered: don't store the new token.
        guard generation == driveGeneration else { throw GoogleClient.Failure.cancelled }
        if tokens.refresh != refresh, !Keychain.save(tokens.refresh, account: Self.driveTokenAccount) {
            throw GoogleClient.Failure.expired
        }
        driveAccess = tokens
        return GoogleDriveFiles(access: tokens.access)
    }
}
