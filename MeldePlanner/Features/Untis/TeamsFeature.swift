import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Microsoft Teams: assignments become homework. Listed once switched on in Einstellungen.
    static var teams: MeldoFeature {
        var feature = MeldoFeature(id: "teams", title: { L("Microsoft Teams") }, symbol: "person.3", placement: .connections) {
            TeamsConnectView()
        }
        feature.isAvailable = { $0.teamsAvailable }
        feature.settingsSection = { AnyView(TeamsSettingsSection()) }
        feature.install = { $0.installTeams() }
        // Not every half minute: Teams checks at most every three hours anyway.
        feature.refresh = { model, reason in
            if reason != .periodic { await model.refreshTeamsIfStale() }
        }
        return feature
    }
}

/// Teams stays off until the student turns it on: many schools must allow it first.
private struct TeamsSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle(L("Microsoft Teams"), isOn: Binding(get: { model.preferences.teamsEnabled }, set: { model.setTeamsEnabled($0) }))
        } header: {
            Text(L("Erweitert"))
        } footer: {
            Text(L("Schalte das nur ein, wenn deine Schule Meldo für Teams freigegeben hat. Viele Schulen müssen das erst erlauben."))
        }
    }
}
