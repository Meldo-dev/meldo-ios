import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Kalender: exams, tasks, absences and Meldungen by day.
    public static var calendar: MeldoFeature {
        MeldoFeature(id: "calendar", title: { L("Kalender") }, symbol: "calendar", placement: .bar) {
            CalendarView()
        }
    }
}
