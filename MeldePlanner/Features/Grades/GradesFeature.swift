import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Noten: the student's own grade calculator.
    static var grades: MeldoFeature {
        var feature = MeldoFeature(id: "grades", title: { L("Noten") }, symbol: "graduationcap", placement: .bar) {
            GradesView()
        }
        feature.dashboardCards = [
            DashboardCardProvider(.grades, title: { L("Notenschnitt") }, symbol: "graduationcap") { _, size in GradesCard(size: size) },
        ]
        return feature
    }
}
