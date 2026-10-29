import MeldoKit
import MeldoState
import SwiftUI

/// Where a feature shows up in the navigation.
public enum FeaturePlacement: Sendable {
    /// Always in the tab bar (Start, Stundenplan).
    case pinned
    /// One of the places the student can put into the tab bar's two flexible slots;
    /// otherwise listed under Schule.
    case bar
    /// Listed under Schule.
    case school
    /// Listed under Verbindungen.
    case connections
    /// Listed under App.
    case app
    /// No place in the navigation (Melden's button, the first-run tour).
    case hidden
}

/// A screen one feature opens in another. A route whose feature isn't built in
/// has no destination, and the button or link for it doesn't show.
public enum MeldoRoute: Hashable, Sendable {
    /// A feature's own screen, by feature id.
    case page(String)
    /// A new task, optionally for a subject (due at its next lesson).
    case newTask(kind: TaskKind, subjectID: UUID?)
    /// A new subject.
    case newSubject
    /// A new lesson on a weekday (Monday = 0).
    case newLesson(weekday: Int)
}

/// Why the app asks features to bring their data up to date.
public enum RefreshReason: Sendable {
    /// iOS woke the app in the background (Background App Refresh).
    case background
    /// The app came to the foreground.
    case foreground
    /// Every half minute while the app is open.
    case periodic
}

/// A card a feature adds to the Start screen.
public struct DashboardCardProvider {
    public var kind: DashboardCard
    public var title: () -> String
    public var symbol: String
    public var content: (_ now: Date, _ size: CardSize) -> AnyView

    public init<Content: View>(_ kind: DashboardCard, title: @escaping () -> String, symbol: String,
                               @ViewBuilder content: @escaping (_ now: Date, _ size: CardSize) -> Content) {
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.content = { AnyView(content($0, $1)) }
    }
}

/// One module of the app as the navigation, Start, Einstellungen and the tour see it.
/// The app target lists the features it's built with; nothing else names them.
public struct MeldoFeature: Identifiable {
    public var id: String
    public var title: () -> String
    public var symbol: String
    public var placement: FeaturePlacement
    /// Its row under Mehr, when that says more than the tab title.
    public var moreTitle: (() -> String)?
    /// The feature's screen.
    public var page: () -> AnyView
    /// The screen extends under the floating Melden button instead of leaving room for it.
    public var fillsScreen = false
    /// On a wide screen this place stays in the top bar even when it isn't one of the two chosen.
    public var alwaysInWideBar = false
    /// Listed only while this holds (Teams once it's switched on).
    public var isAvailable: (AppModel) -> Bool = { _ in true }
    /// A count on its tab, its sidebar row and on Mehr (something needs the student).
    public var badge: (AppModel) -> Int = { _ in 0 }
    /// A short status next to its row under Mehr ("An", "Aus").
    public var statusLabel: ((AppModel) -> AnyView)?
    /// Cards it adds to Start.
    public var dashboardCards: [DashboardCardProvider] = []
    /// A section it adds to Einstellungen.
    public var settingsSection: (() -> AnyView)?
    /// Screens it offers to other features.
    public var destination: (MeldoRoute) -> AnyView? = { _ in nil }
    /// The button Start and Stundenplan float (Melden). `inAccessory` is the tab bar's accessory.
    public var floatingAction: ((_ inAccessory: Bool) -> AnyView)?
    /// Brings the feature's outside data up to date (WebUntis, Teams, Google Drive).
    public var refresh: ((AppModel, RefreshReason) async -> Void)?
    /// Refreshes run in this order, lowest first (Drive syncs first, so a disconnect made
    /// on another device is seen before anything else refreshes).
    public var refreshOrder = 1
    /// Asks iOS to wake the app more often in the background (Drive sync is on).
    public var wantsFrequentWakeUps: () -> Bool = { false }
    /// Fills in sample data for the UI tests and screenshots (debug builds).
    public var seedSample: ((AppModel, _ now: Date) -> Void)?
    /// Connects the feature to the model at launch (its state, change and merge hooks).
    public var install: (AppModel) -> Void = { _ in }
    /// Keychain accounts a fresh install forgets even when restored data still has a connection.
    public var perInstallSecrets: [String] = []

    public init<Page: View>(id: String, title: @escaping () -> String, symbol: String, placement: FeaturePlacement,
                            @ViewBuilder page: @escaping () -> Page) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.placement = placement
        self.page = { AnyView(page()) }
    }
}

/// The features this build contains, in navigation order.
public struct MeldoFeatures {
    public var all: [MeldoFeature]

    public init(_ all: [MeldoFeature]) {
        self.all = all
    }

    public func feature(_ id: String) -> MeldoFeature? {
        all.first { $0.id == id }
    }

    public func placed(_ placement: FeaturePlacement) -> [MeldoFeature] {
        all.filter { $0.placement == placement }
    }

    /// The screen for `route`, or `nil` when no feature in this build offers it.
    public func destination(_ route: MeldoRoute) -> AnyView? {
        if case .page(let id) = route, let feature = feature(id) { return feature.page() }
        for feature in all {
            if let view = feature.destination(route) { return view }
        }
        return nil
    }

    public func has(_ route: MeldoRoute) -> Bool {
        if case .page(let id) = route { return feature(id) != nil }
        return destination(route) != nil
    }

    /// The places the student can put into the tab bar's two flexible slots.
    public var barChoices: [MeldoFeature] { placed(.bar) }

    /// The two places chosen in Einstellungen; the first two choices until then.
    public func barSlots(_ preferences: Preferences) -> [MeldoFeature] {
        let choices = barChoices
        let chosen = preferences.barTabs.compactMap { id in choices.first { $0.id == id } }
        return chosen.count == 2 && chosen[0].id != chosen[1].id ? chosen : Array(choices.prefix(2))
    }

    /// A wide screen's top bar after the pinned tabs: the two places, then the ones it always keeps.
    public func wideBar(_ preferences: Preferences) -> [MeldoFeature] {
        let slots = barSlots(preferences)
        return slots + barChoices.filter { choice in choice.alwaysInWideBar && !slots.contains { $0.id == choice.id } }
    }

    /// Schule: every place that isn't in `bar`, then the ones that are only listed.
    public func schoolPlaces(notIn bar: [MeldoFeature]) -> [MeldoFeature] {
        barChoices.filter { choice in !bar.contains { $0.id == choice.id } } + placed(.school)
    }

    public var dashboardCards: [DashboardCardProvider] {
        all.flatMap(\.dashboardCards)
    }

    public func dashboardCard(_ kind: DashboardCard) -> DashboardCardProvider? {
        dashboardCards.first { $0.kind == kind }
    }

    /// Lets every feature bring its outside data up to date, in `refreshOrder`.
    public func refresh(_ model: AppModel, reason: RefreshReason) async {
        for feature in all.sorted(by: { $0.refreshOrder < $1.refreshOrder }) {
            await feature.refresh?(model, reason)
        }
    }

    /// Connects every feature to a new model. Keychain items outlive the app, so a fresh
    /// install first forgets what an earlier one left behind.
    public func install(in model: AppModel) {
        if model.hasReadableStore {
            Keychain.forgetEarlierInstall(hasConnection: model.data.untis != nil || model.data.teams != nil,
                                          alwaysForget: all.flatMap(\.perInstallSecrets))
        }
        all.forEach { $0.install(model) }
    }
}

public extension EnvironmentValues {
    /// The features of this build.
    @Entry var features = MeldoFeatures([])
    /// Taps on a tab that's already open; Stundenplan goes back to today on each.
    @Entry var tabReselections = 0
}

/// A link to a route, shown only when a feature in this build offers it.
public struct RouteLink<Label: View>: View {
    @Environment(\.features) private var features
    private let route: MeldoRoute
    private let label: Label

    public init(_ route: MeldoRoute, @ViewBuilder label: () -> Label) {
        self.route = route
        self.label = label()
    }

    public var body: some View {
        if let destination = features.destination(route) {
            NavigationLink { destination } label: { label }
        }
    }
}

public extension RouteLink where Label == Text {
    init(_ title: String, route: MeldoRoute) {
        self.init(route) { Text(title) }
    }
}

public extension View {
    /// Presents `route`'s screen as a sheet while `isPresented` is true.
    func sheet(_ route: MeldoRoute, isPresented: Binding<Bool>) -> some View {
        modifier(RouteSheet(route: route, isPresented: isPresented))
    }
}

private struct RouteSheet: ViewModifier {
    @Environment(\.features) private var features
    let route: MeldoRoute
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) { features.destination(route) }
    }
}
