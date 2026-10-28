import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// The first-run tour, shown as a sheet by the app and again from Mehr.
    public static var onboarding: MeldoFeature {
        MeldoFeature(id: "onboarding", title: { L("Einführung ansehen") }, symbol: "sparkles", placement: .hidden) {
            OnboardingView()
        }
    }
}
