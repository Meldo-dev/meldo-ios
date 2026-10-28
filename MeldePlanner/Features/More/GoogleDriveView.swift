import AuthenticationServices
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Google Drive sync and backup: sign in, set or enter the backup password, then
/// Meldo keeps the encrypted backup current on its own.
struct GoogleDriveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var working = false
    @State private var message: String?
    @State private var password = ""
    @State private var repeated = ""
    /// Whether this Google account already has a Meldo backup; nil while checking.
    @State private var hasBackup: Bool?
    /// The check failed (offline, or a damaged backup); `checks` restarts it.
    @State private var checkFailed = false
    @State private var checks = 0
    @State private var confirmingDelete = false
    /// Counts wrong or unusable passwords: each one shakes the fields and buzzes.
    @State private var failures = 0

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DS.spacingM) {
                    Label(L("Backup in Google Drive"), systemImage: "externaldrive")
                        .font(.headline)
                    Text(Self.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DS.spacingXS)
            }
            if !GoogleConfig.isConfigured {
                Section {
                    Label(L("In dieser Version noch nicht verfügbar."), systemImage: "externaldrive.badge.xmark")
                        .foregroundStyle(.secondary)
                }
            } else {
                if model.driveState != .off, let account = model.driveAccount {
                    Section {
                        LabeledContent(L("Konto"), value: account)
                    }
                }
                switch model.driveState {
                case .off: signInSection
                case .needsPassword: passwordSection
                case .on: statusSection
                }
            }
            // Password problems show right under the password button instead.
            if let message, model.driveState != .needsPassword {
                Text(message).foregroundStyle(.red)
            }
        }
        .sensoryFeedback(.error, trigger: failures) { _, _ in model.preferences.haptics }
        .navigationTitle(L("Google Drive"))
        .confirmationDialog(L("Backup in Google Drive löschen?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L("Backup löschen"), role: .destructive) { Task { await deleteBackup() } }
        } message: {
            Text(L("Das Backup verschwindet für alle deine Geräte. Die Daten auf diesem Gerät bleiben."))
        }
        .onChange(of: model.driveState) {
            // What was checked belongs to the old state.
            hasBackup = nil
            checkFailed = false
        }
        .task(id: "\(model.driveState)-\(checks)") {
            guard model.driveState == .needsPassword, hasBackup == nil else { return }
            checkFailed = false
            do {
                hasBackup = try await model.driveHasBackup()
            } catch BackupKey.Problem.damaged {
                checkFailed = true
                message = L("Das Backup in Google Drive ist beschädigt.")
            } catch let failure as GoogleClient.Failure {
                checkFailed = true
                message = Self.text(for: failure)
            } catch {
                checkFailed = true
                message = Self.text(for: .network)
            }
        }
    }

    private static var explanation: String {
        L("Sichert Fächer, Stundenplan, Meldungen, Noten, Aufgaben und Dokumente in deinem Google Drive und gleicht sie zwischen deinen Geräten ab. Meldo sieht nur seinen eigenen versteckten Ordner, nicht deine anderen Dateien.")
    }

    @ViewBuilder
    private var signInSection: some View {
        Section {
            // Before sign-in, in a color that stands out: everything goes to Drive, encrypted.
            HStack(alignment: .top, spacing: DS.spacingM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    Text(L("Alle Daten werden gesichert"))
                        .font(.headline)
                    Text(L("Meldo lädt alles in dein Google Drive: Fächer, Stundenplan, Meldungen, Noten, Aufgaben, Abwesenheiten und Dokumente. Vorher wird alles auf deinem Gerät mit deinem Backup-Passwort verschlüsselt, sodass Google nichts lesen kann. Passwörter und Anmeldungen bleiben auf dem Gerät."))
                        .font(.subheadline)
                }
            }
            .padding(.vertical, DS.spacingXS)
            .listRowBackground(Color.orange.opacity(0.18))
            .accessibilityElement(children: .combine)
        }
        Section {
            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    Label(L("Mit Google anmelden"), systemImage: "person.crop.circle.badge.plus")
                    if working { Spacer(); ProgressView() }
                }
            }
            .disabled(working)
        }
    }

    @ViewBuilder
    private var passwordSection: some View {
        // Signed in but nothing is saved yet: the one step left must stand out.
        Section {
            HStack(alignment: .top, spacing: DS.spacingM) {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    Text(L("Fast fertig: Gib dein Backup-Passwort ein"))
                        .font(.headline)
                    Text(L("Ohne Passwort sichert Meldo nichts. Hast du auf einem anderen Gerät schon ein Backup, nimm dasselbe Passwort."))
                        .font(.subheadline)
                }
            }
            .padding(.vertical, DS.spacingXS)
            .listRowBackground(Color.orange.opacity(0.18))
            .accessibilityElement(children: .combine)
        }
        if let problem = model.driveProblem {
            Section {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
        Section {
            if let hasBackup {
                SecureField(L("Backup-Passwort"), text: $password)
                    .textContentType(hasBackup ? .password : .newPassword)
                    .modifier(Shake(trigger: failures))
                if !hasBackup {
                    SecureField(L("Passwort wiederholen"), text: $repeated)
                        .textContentType(.newPassword)
                        .modifier(Shake(trigger: failures))
                }
                Button {
                    Task { await unlock(creating: !hasBackup) }
                } label: {
                    HStack {
                        Text(hasBackup ? L("Backup öffnen") : L("Backup erstellen"))
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working || password.isEmpty)
                .modifier(Shake(trigger: failures))
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.weight(.semibold))
                }
            } else if checkFailed {
                Button(L("Erneut versuchen")) {
                    message = nil
                    checks += 1
                }
            } else {
                HStack {
                    Text(L("Wird geprüft …"))
                    Spacer()
                    ProgressView()
                }
            }
        } footer: {
            if hasBackup == true {
                Text(L("Gib das Backup-Passwort ein, das du auf deinem anderen Gerät gewählt hast. Passwort vergessen? Dann lösche das Backup und lege ein neues an."))
            } else {
                Text(L("Dein Backup wird mit diesem Passwort auf dem Gerät verschlüsselt, bevor es zu Google geht. Google kann es nicht lesen. Ohne das Passwort lässt es sich nicht wiederherstellen. Mindestens 8 Zeichen."))
            }
        }
        Section {
            // Also the way out of a damaged backup.
            if hasBackup == true || checkFailed {
                Button(L("Backup in Google Drive löschen"), role: .destructive) { confirmingDelete = true }
                    .disabled(working)
            }
            Button(L("Google Drive trennen"), role: .destructive) { disconnect() }
                .disabled(working)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            LabeledContent(L("Zuletzt gesichert")) {
                if model.isSyncingWithDrive {
                    Text(L("Wird gesichert …"))
                } else if let last = model.lastDriveSync {
                    Text(last, style: .relative)
                } else {
                    Text(L("Noch nie"))
                }
            }
            Button {
                Task { await model.syncWithGoogleDrive() }
            } label: {
                HStack {
                    Label(L("Jetzt sichern"), systemImage: "arrow.triangle.2.circlepath")
                    if model.isSyncingWithDrive { Spacer(); ProgressView() }
                }
            }
            .disabled(model.isSyncingWithDrive)
        } footer: {
            VStack(alignment: .leading, spacing: DS.spacingXS) {
                if let problem = model.driveProblem {
                    Text(problem).foregroundStyle(.red)
                }
                Text(L("Meldo sichert nach jeder Änderung und beim Öffnen. Passwörter für WebUntis und Teams bleiben auf jedem Gerät."))
            }
        }
        Section {
            Button(L("Google Drive trennen"), role: .destructive) { disconnect() }
                .disabled(model.isSyncingWithDrive || working)
            Button(L("Backup in Google Drive löschen"), role: .destructive) { confirmingDelete = true }
                .disabled(model.isSyncingWithDrive || working)
        }
    }

    private func signIn() async {
        guard let auth = GoogleClient.authorization() else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: auth.url,
                callbackURLScheme: GoogleConfig.callbackScheme,
                // No shared browser cookies: after "trennen" no Google sign-in stays behind.
                preferredBrowserSession: .ephemeral
            )
            let code = try GoogleClient.code(from: callback, state: auth.state)
            try await model.connectGoogle(code: code, verifier: auth.verifier)
            hasBackup = nil
        } catch let failure as GoogleClient.Failure {
            message = Self.text(for: failure)
        } catch {
            // The student closed Google's page.
            message = nil
        }
    }

    private func unlock(creating: Bool) async {
        if creating, password != repeated {
            message = L("Die Passwörter stimmen nicht überein.")
            failures += 1
            return
        }
        working = true
        message = nil
        defer { working = false }
        do {
            try await model.unlockDrive(password: password, creating: creating)
            password = ""
            repeated = ""
        } catch let problem as BackupKey.Problem {
            message = switch problem {
            case .wrongPassword: L("Falsches Passwort.")
            case .tooShort: L("Das Passwort braucht mindestens 8 Zeichen.")
            case .damaged: L("Das Backup in Google Drive ist beschädigt.")
            case .notSaved: L("Der Schlüssel konnte auf diesem Gerät nicht gespeichert werden. Versuche es noch einmal.")
            }
            failures += 1
        } catch DriveSync.Problem.keyChanged {
            // The backup appeared or vanished meanwhile: check again, then ask again.
            message = L("Das Backup wurde auf einem anderen Gerät gelöscht oder neu angelegt. Gib das Backup-Passwort ein.")
            hasBackup = nil
            checks += 1
        } catch let failure as GoogleClient.Failure {
            message = Self.text(for: failure)
        } catch {
            message = Self.text(for: .network)
        }
    }

    private func deleteBackup() async {
        working = true
        message = nil
        defer { working = false }
        do {
            try await model.deleteDriveBackup()
            hasBackup = nil
            checkFailed = false
        } catch let failure as GoogleClient.Failure {
            message = Self.text(for: failure)
        } catch {
            message = Self.text(for: .network)
        }
    }

    private func disconnect() {
        model.disconnectGoogle()
        password = ""
        repeated = ""
        hasBackup = nil
        message = nil
    }

    static func text(for failure: GoogleClient.Failure) -> String {
        switch failure {
        case .notConfigured: L("In dieser Version noch nicht verfügbar.")
        case .cancelled: L("Anmeldung abgebrochen.")
        case .denied: L("Google hat die Anfrage abgelehnt.")
        case .expired: L("Deine Google-Anmeldung ist abgelaufen. Melde dich erneut an.")
        case .network: L("Keine Verbindung zu Google. Prüfe dein Internet.")
        }
    }
}

/// A short sideways shake when `trigger` changes, like a wrong passcode. Off with Reduce Motion.
private struct Shake: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
            view.offset(x: reduceMotion ? 0 : x)
        } keyframes: { _ in
            KeyframeTrack {
                for x in [-12.0, 10, -8, 6, -3, 0] { LinearKeyframe(x, duration: 0.06) }
            }
        }
    }
}
