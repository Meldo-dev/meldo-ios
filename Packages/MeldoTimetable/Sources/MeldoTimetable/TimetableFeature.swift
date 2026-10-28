import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Stundenplan, and the lesson editor other screens open.
    public static var timetable: MeldoFeature {
        var feature = MeldoFeature(id: "timetable", title: { L("Stundenplan") }, symbol: "tablecells", placement: .pinned) {
            TimetableView()
        }
        feature.fillsScreen = true
        feature.destination = { route in
            guard case .newLesson(let weekday) = route else { return nil }
            return AnyView(LessonEditorView(lesson: nil, weekday: weekday))
        }
        return feature
    }
}
