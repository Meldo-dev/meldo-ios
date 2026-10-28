import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Start: the cards the student arranges.
    public static var dashboard: MeldoFeature {
        var feature = MeldoFeature(id: "home", title: { L("Start") }, symbol: "house", placement: .pinned) {
            DashboardView()
        }
        feature.dashboardCards = [
            DashboardCardProvider(.today, title: { L("Heute") }, symbol: "sun.max") { TodayCard(now: $0, size: $1) },
            DashboardCardProvider(.weekPreview, title: { L("Woche") }, symbol: "calendar.day.timeline.left") { WeekPreviewCard(now: $0, size: $1) },
            DashboardCardProvider(.participation, title: { L("Meldungen diese Woche") }, symbol: "hand.raised") { WeekParticipationCard(now: $0, size: $1) },
            DashboardCardProvider(.streak, title: { L("Serie") }, symbol: "flame") { StreakCard(now: $0, size: $1) },
            DashboardCardProvider(.nextLesson, title: { L("Nächste Stunde") }, symbol: "clock") { NextLessonCard(now: $0, size: $1) },
            DashboardCardProvider(.weekChart, title: { L("Wochenverlauf") }, symbol: "chart.bar.xaxis") { WeekChartMiniCard(now: $0, size: $1) },
        ]
        return feature
    }
}
