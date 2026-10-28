import Foundation
import WidgetKit

/// Everything outside the app that shows Meldo data.
public nonisolated enum Surfaces: Sendable {
    public static let widgetKind = "MeldoToday"
    public static let controlKind = "app.meldeplanner.ios.melden"

    /// Refreshes widgets and the Melden control after data changed.
    public static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}

nonisolated extension Notification.Name {
    /// Posted when data changed outside the app's own model (notification actions).
    public static let meldeDataChanged = Notification.Name("app.meldeplanner.dataChanged")
}

/// Deep links into the app (`meldeplanner://…`).
public nonisolated enum DeepLink: Sendable {
    public static let scheme = "meldeplanner"
    /// Opens the subject picker to log a Meldung outside a lesson.
    public static let melden = URL(string: "meldeplanner://melden")!
    public static let homework = URL(string: "meldeplanner://hausaufgaben")!
}
