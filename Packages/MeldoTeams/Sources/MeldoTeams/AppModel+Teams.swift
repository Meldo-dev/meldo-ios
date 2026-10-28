import Foundation
import MeldoKit
import MeldoState
import MeldoUI

/// Teams import status on this device.
final class TeamsSession {
    /// Bumped by "Teams trennen". An import that started earlier stops writing,
    /// so it can't bring back the connection or its secret.
    var generation = 0
}

/// Microsoft Teams assignments become homework in Aufgaben.
extension AppModel {
    private static let teamsKeychainAccount = "microsoft-teams"

    var teamsGeneration: Int {
        get { moduleState(TeamsSession.init).generation }
        set { moduleState(TeamsSession.init).generation = newValue }
    }

    /// Teams is offered once switched on, or while a connection from before still exists.
    var teamsAvailable: Bool { preferences.teamsEnabled || data.teams != nil }

    func setTeamsEnabled(_ on: Bool) {
        mutate { $0.preferences.teamsEnabled = on }
    }

    /// Disconnected on another device: this device's secret goes too.
    func installTeams() {
        onMerge { [weak self] before in
            guard let self, before.teams != nil, data.teams == nil else { return }
            forgetTeamsSecret()
        }
    }

    var teamsLink: TeamsLink? { data.teams }

    /// Finishes sign-in with the code from Microsoft's redirect, then imports.
    @discardableResult
    func connectTeams(code: String, verifier: String) async throws(TeamsClient.Failure) -> Int {
        let generation = teamsGeneration
        let client = TeamsClient()
        let tokens = try await client.redeem(code: code, verifier: verifier)
        let account = (try? await client.accountName(access: tokens.access)) ?? ""
        guard generation == teamsGeneration else { throw .cancelled }
        _ = Keychain.save(tokens.refresh, account: Self.teamsKeychainAccount)
        mutate { $0.teams = TeamsLink(account: account) }
        return try await importTeams(client: client, access: tokens.access, generation: generation)
    }

    /// Re-imports with the stored refresh token. Returns the number of new assignments.
    @discardableResult
    func refreshTeams() async throws(TeamsClient.Failure) -> Int {
        guard data.teams != nil, let refresh = Keychain.read(account: Self.teamsKeychainAccount) else { return 0 }
        let generation = teamsGeneration
        let client = TeamsClient()
        let tokens = try await client.refresh(refresh)
        // "Teams trennen" while Microsoft answered: don't store the new token.
        guard generation == teamsGeneration else { throw .cancelled }
        if !tokens.refresh.isEmpty { _ = Keychain.save(tokens.refresh, account: Self.teamsKeychainAccount) }
        return try await importTeams(client: client, access: tokens.access, generation: generation)
    }

    /// At most every three hours, when the app comes to the foreground.
    func refreshTeamsIfStale() async {
        guard TeamsConfig.isConfigured, let link = data.teams else { return }
        if let last = link.lastSync, (0..<TimeInterval(3 * 3600)).contains(currentDate.timeIntervalSince(last)) { return }
        _ = try? await refreshTeams()
    }

    func disconnectTeams() {
        forgetTeamsSecret()
        mutate { $0.teams = nil }
    }

    /// Deletes the refresh token and stops imports that are still running.
    func forgetTeamsSecret() {
        teamsGeneration += 1
        Keychain.delete(account: Self.teamsKeychainAccount)
    }

    /// Adds assignments Meldo hasn't seen; tasks already imported stay as the
    /// student left them (done, edited, deleted ones aren't brought back).
    private func importTeams(client: TeamsClient, access: String, generation: Int) async throws(TeamsClient.Failure) -> Int {
        let assignments = try await client.assignments(access: access)
        guard generation == teamsGeneration else { throw .cancelled }
        let calendar = calendar
        let now = currentDate
        var added = 0
        mutate { data in
            var seen = Set(data.tasks.compactMap(\.teamsID))
            for a in assignments where !seen.contains(a.id) && !a.title.isEmpty && !data.dismissedImports.contains("teams:\(a.id)") {
                let subject = data.subjects.first { subject in
                    !a.className.isEmpty && (a.className.localizedCaseInsensitiveContains(subject.name)
                        || (subject.untisKey.map { a.className.localizedCaseInsensitiveContains($0) } ?? false))
                }
                var notes = a.className
                if !a.instructions.isEmpty { notes += notes.isEmpty ? a.instructions : "\n\n\(a.instructions)" }
                data.tasks.append(SchoolTask(
                    title: a.title, notes: notes, kind: .homework, subjectID: subject?.id,
                    dueDate: a.due.map { calendar.startOfDay(for: $0) }, teamsID: a.id
                ))
                seen.insert(a.id)
                added += 1
            }
            data.teams?.lastSync = now
        }
        return added
    }
}
