import Foundation
import WidgetKit

/// Everything outside the app that shows Meldo data.
nonisolated enum Surfaces {
    static let widgetKind = "MeldoToday"
    static let controlKind = "app.meldeplanner.ios.melden"

    /// Refreshes widgets and the Melden control after data changed.
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}

nonisolated extension Notification.Name {
    /// Posted when data changed outside the app's own model (notification actions).
    static let meldeDataChanged = Notification.Name("app.meldeplanner.dataChanged")
}

/// Deep links into the app (`meldeplanner://…`).
nonisolated enum DeepLink {
    static let scheme = "meldeplanner"
    /// Opens the subject picker to log a Meldung outside a lesson.
    static let melden = URL(string: "meldeplanner://melden")!
    static let homework = URL(string: "meldeplanner://hausaufgaben")!
}
