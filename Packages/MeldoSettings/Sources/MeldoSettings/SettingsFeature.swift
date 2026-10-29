import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Einstellungen.
    public static var settings: MeldoFeature {
        MeldoFeature(id: "settings", title: { L("Einstellungen") }, symbol: "gearshape", placement: .app) {
            SettingsView()
        }
    }

    /// Status: widgets, notifications and the Live Activity checked on this device.
    public static var status: MeldoFeature {
        var feature = MeldoFeature(id: "status", title: { L("Status") }, symbol: "stethoscope", placement: .app) {
            StatusView()
        }
        feature.moreTitle = { L("Status: Widgets, Mitteilungen") }
        return feature
    }

    /// WebUntis under Verbindungen: says the import waits for approval from Untis.
    public static var untis: MeldoFeature {
        MeldoFeature(id: "untis", title: { L("WebUntis") }, symbol: "arrow.triangle.2.circlepath", placement: .connections) {
            UntisPendingView()
        }
    }

    /// Über Meldo: version, privacy policy.
    public static var about: MeldoFeature {
        MeldoFeature(id: "about", title: { L("Über Meldo") }, symbol: "info.circle", placement: .app) {
            AboutView()
        }
    }
}
