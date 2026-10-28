import MeldoKit
import MeldoState
import SwiftUI

/// The Mehr tab (iPhone, and iPad with the sidebar collapsed): every feature that
/// isn't in the tab bar. The iPad sidebar lists the same destinations directly.
public struct MoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.features) private var features
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init() {}

    public var body: some View {
        List {
            // Everything that isn't in the tab bar (the student picks the bar's two places).
            // iPad's bar also keeps Dokumente.
            let bar = sizeClass == .regular ? features.wideBar(model.preferences) : features.barSlots(model.preferences)
            section(L("Schule"), features.schoolPlaces(notIn: bar))
            section(L("Verbindungen"), features.placed(.connections).filter { $0.isAvailable(model) })
            Section(L("App")) {
                rows(features.placed(.app))
                if features.feature("onboarding") != nil {
                    Button { model.showOnboardingAgain() } label: {
                        Label(L("Einführung ansehen"), systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("show-onboarding")
                }
            }
        }
        .navigationTitle(L("Mehr"))
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [MeldoFeature]) -> some View {
        if !list.isEmpty {
            Section(title) { rows(list) }
        }
    }

    private func rows(_ list: [MeldoFeature]) -> some View {
        ForEach(list) { feature in
            NavigationLink { feature.page() } label: {
                let label = Label((feature.moreTitle ?? feature.title)(), symbol: feature.symbol)
                if let status = feature.statusLabel {
                    LabeledContent { status(model) } label: { label }
                } else {
                    label
                }
            }
        }
    }
}
