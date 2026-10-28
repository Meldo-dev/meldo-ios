import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// WebUntis: the connection, its Start cards and the Entschuldigung.
    public static var untis: MeldoFeature {
        var feature = MeldoFeature(id: "untis", title: { L("WebUntis") }, symbol: "arrow.triangle.2.circlepath", placement: .connections) {
            UntisConnectView()
        }
        feature.dashboardCards = [
            DashboardCardProvider(.exams, title: { L("Prüfungen") }, symbol: "pencil.and.list.clipboard", needsUntis: true) { UpcomingExamsCard(now: $0, size: $1) },
            DashboardCardProvider(.news, title: { L("Nachrichten") }, symbol: "megaphone", needsUntis: true) { _, size in SchoolNewsCard(size: size) },
            DashboardCardProvider(.absences, title: { L("Abwesenheiten") }, symbol: "person.crop.circle.badge.clock", needsUntis: true) { _, size in AbsencesCard(size: size) },
        ]
        feature.destination = { route in
            guard case .excuseNote(let absence) = route else { return nil }
            return AnyView(ExcuseNoteView(absence: absence))
        }
        feature.install = { $0.installUntis() }
        #if DEBUG
        feature.seedSample = { UntisSampleData.seed($0, now: $1) }
        #endif
        feature.refresh = { model, reason in
            await model.refreshUntisIfStale(maxAge: reason == .background ? AppModel.untisBackgroundRefreshInterval : AppModel.untisRefreshInterval)
        }
        return feature
    }

    /// Abwesenheiten from WebUntis.
    public static var absences: MeldoFeature {
        MeldoFeature(id: "absences", title: { L("Abwesenheiten") }, symbol: "person.crop.circle.badge.clock", placement: .bar) {
            AbsencesView()
        }
    }
}
