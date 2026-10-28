import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Statistik: Meldungen per day, per subject and over the weeks.
    public static var statistics: MeldoFeature {
        MeldoFeature(id: "statistics", title: { L("Statistik") }, symbol: "chart.bar", placement: .bar) {
            StatisticsView()
        }
    }
}
