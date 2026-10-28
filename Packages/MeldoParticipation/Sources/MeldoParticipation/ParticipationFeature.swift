import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Melden: the button Start and Stundenplan float.
    public static var participation: MeldoFeature {
        var feature = MeldoFeature(id: "participation", title: { L("Melden") }, symbol: "hand.raised", placement: .hidden) {
            EmptyView()
        }
        feature.floatingAction = { inAccessory in AnyView(MeldenButton(inAccessory: inAccessory)) }
        return feature
    }
}
