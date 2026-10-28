import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Einstellungen.
    static var settings: MeldoFeature {
        MeldoFeature(id: "settings", title: { L("Einstellungen") }, symbol: "gearshape", placement: .app) {
            SettingsView()
        }
    }

    /// Status: widgets, notifications and the Live Activity checked on this device.
    static var status: MeldoFeature {
        var feature = MeldoFeature(id: "status", title: { L("Status") }, symbol: "stethoscope", placement: .app) {
            StatusView()
        }
        feature.moreTitle = { L("Status: Widgets, Mitteilungen") }
        return feature
    }

    /// Über Meldo: version, privacy policy.
    static var about: MeldoFeature {
        MeldoFeature(id: "about", title: { L("Über Meldo") }, symbol: "info.circle", placement: .app) {
            AboutView()
        }
    }
}
