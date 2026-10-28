import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Ferien from WebUntis, and the countdown card.
    public static var holidays: MeldoFeature {
        var feature = MeldoFeature(id: "holidays", title: { L("Ferien") }, symbol: "sun.horizon", placement: .school) {
            HolidayListView()
        }
        feature.dashboardCards = [
            DashboardCardProvider(.nextHoliday, title: { L("Nächste Ferien") }, symbol: "sun.horizon") { NextHolidayCard(now: $0, size: $1) },
        ]
        return feature
    }
}
