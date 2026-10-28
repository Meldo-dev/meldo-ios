import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Connect WebUntis: find the school, sign in, import. Afterwards: status,
/// refresh and disconnect.
struct UntisConnectView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let link = model.untisLink {
            UntisStatusView(link: link)
        } else {
            UntisSchoolSearchView()
        }
    }
}

private struct UntisSchoolSearchView: View {
    @State private var query = ""
    @State private var schools: [FfiUntisSchool] = []
    @State private var searching = false
    @State private var problem: String?
    /// A gentle note while typing, e.g. that the search is still too general.
    @State private var hint: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.spacingM) {
                    Label(L("Stundenplan aus WebUntis übernehmen"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Text(L("Meldo übernimmt deinen Stundenplan, Ausfälle und Vertretungen aus WebUntis. Dein Login bleibt auf diesem iPhone und geht nur an den WebUntis-Server deiner Schule."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: DS.spacingS) {
                        UntisStep(number: 1, text: L("Schule suchen und antippen"), active: true)
                        UntisStep(number: 2, text: L("Mit deinem WebUntis-Login anmelden"), active: false)
                        UntisStep(number: 3, text: L("Meldo importiert deinen Stundenplan"), active: false)
                    }
                }
                .padding(.vertical, DS.spacingXS)
            }

            Section {
                HStack(spacing: DS.spacingS) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Schulname und Ort"), text: $query)
                        .focused($searchFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("untis-school-search")
                    if searching {
                        ProgressView()
                    } else if !query.isEmpty {
                        Button(L("Löschen"), systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                    }
                }
                if let hint {
                    Label(hint, systemImage: "text.magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                ForEach(schools, id: \.loginName) { school in
                    NavigationLink {
                        UntisLoginView(school: school)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(school.displayName).font(.body.weight(.semibold))
                            if !school.address.isEmpty {
                                Text(school.address).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(L("1. Schule finden"))
            } footer: {
                Text(L("Gib den Namen deiner Schule zusammen mit dem Ort ein, zum Beispiel „Gymnasium Köln-Pesch“. Bei zu allgemeinen Suchen zeigt WebUntis keine Liste an."))
            }
        }
        .navigationTitle(L("WebUntis"))
        .task(id: query) { await search() }
        .onAppear { if query.isEmpty { searchFocused = true } }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            schools = []
            problem = nil
            hint = nil
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            schools = try await UntisClient().searchSchools(trimmed)
            problem = nil
            hint = schools.isEmpty ? L("Keine Schule gefunden. Prüfe die Schreibweise oder versuche nur Schulart und Ort.") : nil
        } catch .tooManyResults {
            // Normal while typing: WebUntis lists nothing until the search is specific enough.
            schools = []
            problem = nil
            hint = L("Zu viele Schulen gefunden. Gib mehr vom Namen und den Ort ein, zum Beispiel „Gymnasium Köln-Pesch“.")
        } catch {
            schools = []
            hint = nil
            problem = UntisMessages.text(for: error)
        }
    }
}

private struct UntisLoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let school: FfiUntisSchool

    @State private var user = ""
    @State private var password = ""
    @State private var working = false
    @State private var problem: String?
    @State private var browserLogin = false

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Schule"), value: school.displayName)
                Button {
                    browserLogin = true
                } label: {
                    Label(L("Mit Microsoft 365 oder Schul-Login anmelden"), systemImage: "person.badge.key.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(working)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text(L("2. Anmelden"))
            } footer: {
                Text(L("Für Schulen, bei denen du dich bei WebUntis mit Microsoft 365, IServ oder einer anderen Seite anmeldest. Du meldest dich auf der echten Seite deiner Schule an; Meldo sieht dein Passwort nie."))
            }
            Section {
                TextField(L("Benutzername"), text: $user)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(L("Passwort"), text: $password)
                    .textContentType(.password)
            } header: {
                Text(L("Oder mit WebUntis-Benutzername"))
            } footer: {
                Text(L("Derselbe Benutzername und dasselbe Passwort wie auf der WebUntis-Seite oder in der Untis-App deiner Schule. Das Passwort wird nur im Schlüsselbund dieses iPhones gespeichert."))
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text(L("Verbinden und importieren"))
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working || user.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle(L("Anmelden"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $browserLogin) {
            UntisWebLoginView(school: school) { server, cookies, sessionID, ssoPath in
                browserLogin = false
                Task { await connectWithBrowser(server: server, cookies: cookies, sessionID: sessionID, ssoPath: ssoPath) }
            }
        }
    }

    private func connectWithBrowser(server: String, cookies: String, sessionID: String, ssoPath: String?) async {
        working = true
        problem = nil
        defer { working = false }
        do {
            _ = try await model.connectUntisWithBrowser(school: school, server: server, cookies: cookies, sessionID: sessionID, ssoPath: ssoPath)
            // Done once the import worked: back to WebUntis (now showing the connection), no extra tap.
            dismiss()
        } catch {
            problem = UntisMessages.text(for: error)
        }
    }

    private func connect() async {
        working = true
        problem = nil
        defer { working = false }
        do {
            _ = try await model.connectUntis(school: school, user: user, password: password)
            password = ""
            dismiss()
        } catch {
            problem = UntisMessages.text(for: error)
        }
    }
}

private struct UntisStatusView: View {
    @Environment(AppModel.self) private var model
    let link: UntisLink
    @State private var working = false
    @State private var message: String?
    @State private var confirmingDisconnect = false
    @State private var browserLogin = false

    private var school: FfiUntisSchool {
        FfiUntisSchool(server: link.server, loginName: link.loginName, displayName: link.schoolName, address: "")
    }

    var body: some View {
        List {
            Section {
                LabeledContent(L("Schule"), value: link.schoolName)
                LabeledContent(L("Benutzer"), value: link.browserLogin == true ? L("Schul-Login") : link.user)
                if let last = link.lastSync {
                    LabeledContent(L("Zuletzt aktualisiert")) {
                        // "vor 7 Minuten" instead of a ticking "6 Min., 50 Sek.".
                        TimelineView(.everyMinute) { context in
                            Text(last.formatted(.relative(presentation: .named).locale(Localization.locale)))
                        }
                    }
                }
            } footer: {
                Text(L("Meldo aktualisiert Stundenplan, Ausfälle und Vertretungen automatisch: beim Öffnen, alle 30 Minuten und im Hintergrund."))
            }
            if let message {
                Text(message).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Task {
                        working = true
                        defer { working = false }
                        do {
                            if let s = try await model.refreshUntis() {
                                message = L("Aktualisiert: \(s.lessons) Stunden, \(s.changes) Änderungen.")
                            } else {
                                message = L("Bitte melde dich erneut an.")
                            }
                        } catch {
                            message = UntisMessages.text(for: error)
                        }
                    }
                } label: {
                    HStack {
                        Text(L("Jetzt aktualisieren"))
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working)
                if link.browserLogin == true {
                    Button(L("Erneut mit Schul-Login anmelden"), systemImage: "person.badge.key") { browserLogin = true }
                        .disabled(working)
                }
                Button(L("WebUntis trennen"), role: .destructive) { confirmingDisconnect = true }
                    .disabled(working)
            }
        }
        .navigationTitle(L("WebUntis"))
        .sheet(isPresented: $browserLogin) {
            UntisWebLoginView(school: school) { server, cookies, sessionID, ssoPath in
                browserLogin = false
                Task {
                    working = true
                    defer { working = false }
                    do {
                        let s = try await model.connectUntisWithBrowser(school: school, server: server, cookies: cookies, sessionID: sessionID, ssoPath: ssoPath)
                        message = L("Aktualisiert: \(s.lessons) Stunden, \(s.changes) Änderungen.")
                    } catch {
                        message = UntisMessages.text(for: error)
                    }
                }
            }
        }
        .confirmationDialog(L("WebUntis trennen?"), isPresented: $confirmingDisconnect) {
            Button(L("Trennen"), role: .destructive) { model.disconnectUntis() }
        } message: {
            Text(L("Dein Stundenplan bleibt erhalten, wird aber nicht mehr aktualisiert. Das Passwort wird gelöscht."))
        }
    }
}

enum UntisMessages {
    static func text(for error: any Error) -> String {
        switch error as? UntisClient.Failure {
        case .wrongCredentials: L("Benutzername oder Passwort ist falsch.")
        case .tooManyResults: L("Zu viele Schulen gefunden. Gib mehr vom Namen und den Ort ein, zum Beispiel „Gymnasium Köln-Pesch“.")
        case .network: L("Keine Verbindung zu WebUntis. Prüfe dein Internet.")
        case .sessionExpired: L("Deine WebUntis-Anmeldung ist abgelaufen. Melde dich erneut an.")
        case .noLessons: L("WebUntis zeigt in den nächsten acht Wochen keinen Unterricht für dich, zum Beispiel wegen Ferien. Versuche es später noch einmal.")
        case .server(let code, _): L("WebUntis hat die Anfrage abgelehnt (Code \(code)).")
        case .noAccess, .none: L("Deine Schule erlaubt diesen Zugriff gerade nicht, oder WebUntis wird gewartet.")
        }
    }
}

/// One numbered step of the WebUntis setup.
private struct UntisStep: View {
    let number: Int
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: DS.spacingS) {
            Text(number, format: .number)
                .font(.caption.weight(.bold))
                .foregroundStyle(active ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: .circle)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(active ? .primary : .secondary)
        }
    }
}
