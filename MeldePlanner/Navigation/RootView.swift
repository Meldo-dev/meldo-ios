import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Main navigation, built from the features in this build. iPhone shows the pinned tabs
/// (Start, Stundenplan), the two places the student picks and Mehr. iPad's sidebar lists
/// everything, grouped into Schule, Verbindungen and App; collapsed to a top tab bar it
/// shows the iPhone's tabs plus Dokumente.
/// Melden only appears where you'd use it in class, on the pinned tabs:
/// on iPhone in the tab bar's bottom accessory (it never covers a card),
/// on iPad as a floating button next to the content.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.features) private var features
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Start until `onAppear` applies the opening screen chosen in Einstellungen; an id no tab has
    /// would leave the tab bar out.
    @State private var tab = "home"
    /// Opened by the widget's Melden link outside lessons.
    @State private var pickingSubject = false
    /// Taps on each tab while it's already open (Stundenplan jumps to today on each).
    @State private var reselections: [String: Int] = [:]

    private static let more = "more"

    private var pinned: [MeldoFeature] { features.placed(.pinned) }

    /// The tab bar's two flexible places.
    private var slots: [MeldoFeature] { features.barSlots(model.preferences) }

    /// iPad top bar after the pinned tabs: the two places, then Dokumente.
    private var wideBar: [MeldoFeature] { features.wideBar(model.preferences) }

    private var connections: [MeldoFeature] { features.placed(.connections).filter { $0.isAvailable(model) } }

    /// What Mehr lists needs attention (Google Drive waits for its password).
    private var moreBadge: Int {
        (features.placed(.connections) + features.placed(.app)).reduce(0) { $0 + $1.badge(model) }
    }

    /// The button the pinned tabs float (Melden), if a feature in this build has one.
    private var floatingAction: ((Bool) -> AnyView)? {
        features.all.lazy.compactMap(\.floatingAction).first
    }

    /// Like the system apps: tapping the open tab again (Stundenplan goes back to today).
    private var selection: Binding<String> {
        Binding(get: { tab }, set: { new in
            if new == tab { reselections[new, default: 0] += 1 }
            tab = new
        })
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                TabView(selection: selection) {
                    // Collapsed to a top tab bar, iPad shows the iPhone's tabs plus Dokumente (Mehr holds
                    // the rest); the sidebar lists every destination. Mehr can't be hidden from the
                    // sidebar alone: that needs a customization, which adds an "Edit" button.
                    ForEach(pinned) { feature in
                        Tab(value: feature.id) { screen(feature, melden: true, room: !feature.fillsScreen) } label: { label(feature) }
                    }
                    // The top bar's two flexible places, as on iPhone; iPadOS lists the bar's tabs
                    // first in the sidebar too, the sections below stay fixed.
                    ForEach(wideBar) { feature in
                        Tab(value: feature.id) { screen(feature) } label: { label(feature) }
                    }
                    sidebarSection(L("Schule"), features.schoolPlaces(notIn: wideBar))
                    sidebarSection(L("Verbindungen"), connections)
                    sidebarSection(L("App"), features.placed(.app))
                    // Last: in the sidebar it sits below everything it duplicates; in the
                    // collapsed bar it follows Dokumente (sections are sidebar-only).
                    Tab(value: Self.more) { NavigationStack { MoreView() } } label: { Label(L("Mehr"), systemImage: "ellipsis.circle") }
                        .badge(moreBadge)
                }
                // Sidebar on iPad (switchable to a top tab bar). Fixed placements, no
                // customization: hideable tabs would add an "Edit" button to the sidebar.
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: selection) {
                    ForEach(pinned) { feature in
                        Tab(value: feature.id) { screen(feature) } label: { label(feature) }
                    }
                    // The two places chosen in Einstellungen; everything else is under Mehr.
                    ForEach(slots) { feature in
                        Tab(value: feature.id) { screen(feature) } label: { label(feature) }
                    }
                    Tab(value: Self.more) { NavigationStack { MoreView() } } label: { Label(L("Mehr"), systemImage: "ellipsis.circle") }
                        .badge(moreBadge)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                // Not before the first subject: there would be nothing to record for.
                .modifier(MeldenAccessory(
                    action: floatingAction,
                    enabled: pinned.contains { $0.id == tab } && (!model.subjects.isEmpty || model.data.untis != nil)
                ))
            }
        }
        .onChange(of: sizeClass) { _, newClass in
            // Sidebar-only destinations have no iPhone tab; land on Mehr instead.
            let phoneTabs = (pinned + slots).map(\.id) + [Self.more]
            if newClass == .compact, !phoneTabs.contains(tab) { tab = Self.more }
        }
        .onAppear {
            tab = pinned.first?.id ?? Self.more
            // The screen chosen under Einstellungen › Leiste und Startseite, if it's in the bar.
            if (pinned + slots).contains(where: { $0.id == model.preferences.startTab }) {
                tab = model.preferences.startTab
            }
        }
        .overlay(alignment: .top) {
            if let problem = model.storageProblem {
                StorageBanner(message: problem)
            }
        }
        .onOpenURL(perform: open)
        .sheet(isPresented: $pickingSubject) {
            SubjectPickerSheet { subjectID in
                model.recordParticipation(subjectID: subjectID)
            }
        }
    }

    private func label(_ feature: MeldoFeature) -> some View {
        Label(feature.title(), symbol: feature.symbol)
    }

    @TabContentBuilder<String>
    private func sidebarSection(_ title: String, _ list: [MeldoFeature]) -> some TabContent<String> {
        if !list.isEmpty {
            TabSection(title) {
                ForEach(list) { feature in
                    Tab(value: feature.id) { screen(feature) } label: { label(feature) }
                        .badge(feature.badge(model))
                        .tabPlacement(.sidebarOnly)
                }
            }
            .tabPlacement(.sidebarOnly)
        }
    }

    /// One tab's content in its own navigation stack. With `melden`, the root
    /// screen gets the floating Melden button; screens pushed from it don't.
    /// iPhone on iOS 26.0 has no switchable tab accessory and floats it too.
    /// `room: false` lets the content run under the button (the timetable fills the screen).
    @ViewBuilder
    private func screen(_ feature: MeldoFeature, melden: Bool = false, room: Bool = true) -> some View {
        let content = feature.page().environment(\.tabReselections, reselections[feature.id] ?? 0)
        let floats = melden || (sizeClass != .regular && !MeldenAccessory.available && pinned.contains { $0.id == tab })
        if floats, let floatingAction {
            NavigationStack {
                content
                    .overlay(alignment: .bottomTrailing) { floatingAction(false) }
                    // Room under the last row so the floating button never covers content.
                    .contentMargins(.bottom, room ? 88 : 0, for: .scrollContent)
            }
        } else {
            NavigationStack { content }
        }
    }

    private func open(_ url: URL) {
        guard url.scheme == DeepLink.scheme else { return }
        switch url.host() {
        case "melden":
            // Any app can open this link, so it never records by itself: the student
            // picks the subject (the running lesson is suggested first). The widget
            // records in lessons through LogParticipationIntent instead.
            tab = pinned.first?.id ?? tab
            pickingSubject = true
        case "hausaufgaben":
            if features.feature("tasks") != nil { tab = "tasks" }
        default:
            break
        }
    }
}

private struct StorageBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .padding(DS.spacingM)
            .glassEffect(.regular.tint(.orange.opacity(0.3)), in: .rect(cornerRadius: DS.rowRadius))
            .padding(.horizontal, DS.spacingL)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Melden in the tab bar's bottom accessory on the pinned tabs (iOS 26.1+).
private struct MeldenAccessory: ViewModifier {
    let action: ((Bool) -> AnyView)?
    let enabled: Bool

    static var available: Bool {
        if #available(iOS 26.1, *) { true } else { false }
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *), let action {
            content.tabViewBottomAccessory(isEnabled: enabled) { action(true) }
        } else {
            content
        }
    }
}
