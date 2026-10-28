import AuthenticationServices
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Connect Microsoft Teams: sign in on Microsoft's page, then assignments
/// appear in Aufgaben.
struct TeamsConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var working = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.spacingM) {
                    Label(L("Aufgaben aus Microsoft Teams"), systemImage: "person.3")
                        .font(.headline)
                    Text(L("Meldo übernimmt die Aufgaben deiner Teams-Kurse als Hausaufgaben. Du meldest dich direkt bei Microsoft an; dein Passwort sieht Meldo nie."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DS.spacingXS)
            }
            if !TeamsConfig.isConfigured {
                Section {
                    Label(L("Noch nicht eingerichtet"), systemImage: "wrench.and.screwdriver")
                        .foregroundStyle(.orange)
                    Text(L("Für Teams braucht Meldo eine App-Registrierung bei Microsoft (Azure). Sobald sie eingetragen ist, kannst du dich hier anmelden. Manche Schulen müssen Meldo außerdem freigeben."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let link = model.teamsLink {
                Section {
                    if !link.account.isEmpty {
                        LabeledContent(L("Konto"), value: link.account)
                    }
                    if let last = link.lastSync {
                        LabeledContent(L("Zuletzt aktualisiert")) { Text(last, style: .relative) }
                    }
                } footer: {
                    Text(L("Neue Aufgaben kommen automatisch dazu, wenn du die App öffnest (höchstens alle drei Stunden)."))
                }
                Section {
                    Button {
                        Task { await refresh() }
                    } label: {
                        HStack {
                            Text(L("Jetzt aktualisieren"))
                            if working { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(working)
                    Button(L("Teams trennen"), role: .destructive) { model.disconnectTeams() }
                        .disabled(working)
                }
            } else {
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Label(L("Mit Microsoft anmelden"), systemImage: "person.badge.key.fill")
                                .font(.body.weight(.semibold))
                            if working { Spacer(); ProgressView() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(working)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            if let message {
                Text(message).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("Microsoft Teams"))
    }

    private func signIn() async {
        guard let auth = TeamsClient.authorization() else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: auth.url,
                callbackURLScheme: TeamsConfig.callbackScheme,
                // No shared browser cookies: after "Teams trennen" no Microsoft sign-in stays behind.
                preferredBrowserSession: .ephemeral
            )
            let code = try TeamsClient.code(from: callback, state: auth.state)
            let added = try await model.connectTeams(code: code, verifier: auth.verifier)
            message = L("Verbunden: \(added) Aufgaben übernommen.")
        } catch let failure as TeamsClient.Failure {
            message = Self.text(for: failure)
        } catch {
            // The student closed Microsoft's page.
            message = nil
        }
    }

    private func refresh() async {
        working = true
        defer { working = false }
        do {
            let added = try await model.refreshTeams()
            message = L("Aktualisiert: \(added) neue Aufgaben.")
        } catch {
            message = Self.text(for: error)
        }
    }

    static func text(for failure: TeamsClient.Failure) -> String {
        switch failure {
        case .notConfigured: L("Teams ist in dieser Version noch nicht eingerichtet.")
        case .cancelled: L("Anmeldung abgebrochen.")
        case .denied(let detail):
            detail.isEmpty
                ? L("Microsoft hat die Anfrage abgelehnt. Eventuell muss deine Schule Meldo erst freigeben.")
                : L("Microsoft hat die Anfrage abgelehnt: \(detail)")
        case .expired: L("Deine Microsoft-Anmeldung ist abgelaufen. Melde dich erneut an.")
        case .network: L("Keine Verbindung zu Microsoft. Prüfe dein Internet.")
        }
    }
}
