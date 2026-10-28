import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

enum AppTab: String, Hashable {
    case home, timetable, calendar, tasks, exams, statistics, more
    case absences, holidays, untis, teams, drive, subjects, settings, status, about, grades

    /// What the student can put into the two flexible places of the bar.
    static let barChoices: [AppTab] = [.tasks, .grades, .calendar, .statistics, .exams, .absences]

    /// The two places chosen in Einstellungen; Aufgaben and Noten until then.
    static func barSlots(_ preferences: Preferences) -> [AppTab] {
        let chosen = preferences.barTabs.compactMap(AppTab.init(rawValue:)).filter(barChoices.contains)
        return chosen.count == 2 && chosen[0] != chosen[1] ? chosen : [.tasks, .grades]
    }

    var title: String {
        switch self {
        case .home: L("Start")
        case .timetable: L("Stundenplan")
        case .tasks: L("Aufgaben")
        case .grades: L("Noten")
        case .calendar: L("Kalender")
        case .statistics: L("Statistik")
        case .exams: L("Dokumente")
        case .absences: L("Abwesenheiten")
        case .holidays: L("Ferien")
        default: rawValue
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .timetable: "tablecells"
        case .tasks: "checklist"
        case .grades: "graduationcap"
        case .calendar: "calendar"
        case .statistics: "chart.bar"
        case .exams: "doc.on.doc"
        case .absences: "person.crop.circle.badge.clock"
        case .holidays: "sun.horizon"
        default: "circle"
        }
    }

    /// The screen for a place that can sit in the bar or under Mehr.
    @MainActor @ViewBuilder
    var page: some View {
        switch self {
        case .tasks: TaskListView()
        case .grades: GradesView()
        case .calendar: CalendarView()
        case .statistics: StatisticsView()
        case .exams: ExamListView()
        case .absences: AbsencesView()
        case .holidays: HolidayListView()
        default: EmptyView()
        }
    }
}

/// Main navigation. iPhone shows five tabs (the rest lives under Mehr). iPad's sidebar
/// lists everything, grouped into Schule, Verbindungen and App; collapsed to a top
/// tab bar it shows the iPhone's tabs plus Dokumente.
/// Melden only appears where you'd use it in class, Start and Stundenplan:
/// on iPhone in the tab bar's bottom accessory (it never covers a card),
/// on iPad as a floating button next to the content.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab: AppTab = .home
    /// Opened by the widget's Melden link outside lessons.
    @State private var pickingSubject = false
    /// Counts taps on Stundenplan while it's already open; each one jumps to today.
    @State private var timetableToday = 0

    /// The tab bar's two flexible places.
    private var slots: [AppTab] { AppTab.barSlots(model.preferences) }

    /// iPad top bar after Start and Stundenplan: the two places, then Dokumente.
    private var iPadBar: [AppTab] { slots.contains(.exams) ? slots : slots + [.exams] }

    /// iPad sidebar Schule: every place not in the top bar, then Ferien.
    private var schoolPlaces: [AppTab] { AppTab.barChoices.filter { !iPadBar.contains($0) } + [.holidays] }

    /// Like the system apps: tapping the open tab again takes Stundenplan back to today.
    private var selection: Binding<AppTab> {
        Binding(get: { tab }, set: { new in
            if new == tab, new == .timetable { timetableToday += 1 }
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
                    Tab(value: AppTab.home) { screen(DashboardView(), melden: true) } label: { Label(L("Start"), systemImage: "house") }
                    Tab(value: AppTab.timetable) { screen(TimetableView(todayRequest: timetableToday), melden: true, room: false) } label: { Label(L("Stundenplan"), systemImage: "tablecells") }
                    // The top bar's two flexible places, as on iPhone; iPadOS lists the bar's tabs
                    // first in the sidebar too, the sections below stay fixed.
                    ForEach(iPadBar, id: \.self) { place in
                        Tab(value: place) { screen(place.page) } label: { Label(place.title, systemImage: place.symbol) }
                    }
                    TabSection(L("Schule")) {
                        ForEach(schoolPlaces, id: \.self) { place in
                            Tab(value: place) { screen(place.page) } label: { Label(place.title, systemImage: place.symbol) }
                                .tabPlacement(.sidebarOnly)
                        }
                    }
                    .tabPlacement(.sidebarOnly)
                    TabSection(L("Verbindungen")) {
                        Tab(value: AppTab.untis) { screen(UntisConnectView()) } label: { Label(L("WebUntis"), systemImage: "arrow.triangle.2.circlepath") }
                            .tabPlacement(.sidebarOnly)
                        if model.teamsAvailable {
                            Tab(value: AppTab.teams) { screen(TeamsConnectView()) } label: { Label(L("Microsoft Teams"), systemImage: "person.3") }
                                .tabPlacement(.sidebarOnly)
                        }
                        Tab(value: AppTab.drive) { screen(GoogleDriveView()) } label: { Label(L("Google Drive"), systemImage: "externaldrive") }
                            .badge(model.driveState == .needsPassword ? 1 : 0)
                            .tabPlacement(.sidebarOnly)
                    }
                    .tabPlacement(.sidebarOnly)
                    TabSection(L("App")) {
                        Tab(value: AppTab.subjects) { screen(SubjectListView()) } label: { Label(L("Fächer"), systemImage: "books.vertical") }
                            .tabPlacement(.sidebarOnly)
                        Tab(value: AppTab.settings) { screen(SettingsView()) } label: { Label(L("Einstellungen"), systemImage: "gearshape") }
                            .tabPlacement(.sidebarOnly)
                        Tab(value: AppTab.status) { screen(StatusView()) } label: { Label(L("Status"), systemImage: "stethoscope") }
                            .tabPlacement(.sidebarOnly)
                        Tab(value: AppTab.about) { screen(AboutView()) } label: { Label(L("Über Meldo"), systemImage: "info.circle") }
                            .tabPlacement(.sidebarOnly)
                    }
                    .tabPlacement(.sidebarOnly)
                    // Last: in the sidebar it sits below everything it duplicates; in the
                    // collapsed bar it follows Dokumente (sections are sidebar-only).
                    Tab(value: AppTab.more) { screen(MoreView()) } label: { Label(L("Mehr"), systemImage: "ellipsis.circle") }
                        .badge(model.driveState == .needsPassword ? 1 : 0)
                }
                // Sidebar on iPad (switchable to a top tab bar). Fixed placements, no
                // customization: hideable tabs would add an "Edit" button to the sidebar.
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: selection) {
                    Tab(value: AppTab.home) { screen(DashboardView()) } label: { Label(L("Start"), systemImage: "house") }
                    Tab(value: AppTab.timetable) { screen(TimetableView(todayRequest: timetableToday)) } label: { Label(L("Stundenplan"), systemImage: "tablecells") }
                    // The two places chosen in Einstellungen; everything else is under Mehr.
                    ForEach(slots, id: \.self) { place in
                        Tab(value: place) { screen(place.page) } label: { Label(place.title, systemImage: place.symbol) }
                    }
                    Tab(value: AppTab.more) { screen(MoreView()) } label: { Label(L("Mehr"), systemImage: "ellipsis.circle") }
                        .badge(model.driveState == .needsPassword ? 1 : 0)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                // Not before the first subject: there would be nothing to record for.
                .modifier(MeldenAccessory(enabled: (tab == .home || tab == .timetable) && (!model.subjects.isEmpty || model.data.untis != nil)))
            }
        }
        .onChange(of: sizeClass) { _, newClass in
            // Sidebar-only destinations have no iPhone tab; land on Mehr instead.
            let phoneTabs: [AppTab] = [.home, .timetable] + slots + [.more]
            if newClass == .compact, !phoneTabs.contains(tab) { tab = .more }
        }
        .onAppear {
            // The screen chosen under Einstellungen › Leiste und Startseite, if it's in the bar.
            if let start = AppTab(rawValue: model.preferences.startTab), [.home, .timetable].contains(start) || slots.contains(start) {
                tab = start
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

    /// One tab's content in its own navigation stack. With `melden`, the root
    /// screen gets the floating Melden button; screens pushed from it don't.
    /// iPhone on iOS 26.0 has no switchable tab accessory and floats it too.
    @ViewBuilder
    /// `room: false` lets the content run under the button (the timetable fills the screen).
    private func screen(_ content: some View, melden: Bool = false, room: Bool = true) -> some View {
        if melden || (sizeClass != .regular && !MeldenAccessory.available && [AppTab.home, .timetable].contains(tab)) {
            NavigationStack {
                content
                    .overlay(alignment: .bottomTrailing) { MeldenButton() }
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
            tab = .home
            pickingSubject = true
        case "hausaufgaben":
            tab = .tasks
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

/// Melden in the tab bar's bottom accessory on Start and Stundenplan (iOS 26.1+).
private struct MeldenAccessory: ViewModifier {
    let enabled: Bool

    static var available: Bool {
        if #available(iOS 26.1, *) { true } else { false }
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) { MeldenButton(inAccessory: true) }
        } else {
            content
        }
    }
}
