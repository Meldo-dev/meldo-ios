import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// The Mehr tab (iPhone, and iPad with the sidebar collapsed). The iPad sidebar lists
/// the same destinations directly.
struct MoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        List {
            // Everything that isn't in the tab bar (the student picks the bar's two places).
            Section(L("Schule")) {
                // iPad's bar also keeps Dokumente.
                let slots = AppTab.barSlots(model.preferences) + (sizeClass == .regular ? [.exams] : [])
                ForEach(AppTab.barChoices.filter { !slots.contains($0) } + [.holidays], id: \.self) { place in
                    NavigationLink { place.page } label: {
                        Label(place.title, systemImage: place.symbol)
                    }
                }
            }
            Section(L("Verbindungen")) {
                NavigationLink { UntisConnectView() } label: {
                    Label(L("WebUntis"), systemImage: "arrow.triangle.2.circlepath")
                }
                if model.teamsAvailable {
                    NavigationLink { TeamsConnectView() } label: {
                        Label(L("Microsoft Teams"), systemImage: "person.3")
                    }
                }
                NavigationLink { GoogleDriveView() } label: {
                    LabeledContent {
                        switch model.driveState {
                        case .on: Text(L("An"))
                        case .needsPassword: Text(L("Passwort fehlt")).foregroundStyle(.orange)
                        case .off: Text(L("Aus"))
                        }
                    } label: {
                        Label(L("Google Drive"), systemImage: "externaldrive")
                    }
                }
            }
            Section(L("App")) {
                NavigationLink { SubjectListView() } label: {
                    Label(L("Fächer"), systemImage: "books.vertical")
                }
                NavigationLink { SettingsView() } label: {
                    Label(L("Einstellungen"), systemImage: "gearshape")
                }
                NavigationLink { StatusView() } label: {
                    Label(L("Status: Widgets, Mitteilungen"), systemImage: "stethoscope")
                }
                NavigationLink { AboutView() } label: {
                    Label(L("Über Meldo"), systemImage: "info.circle")
                }
                Button { model.showOnboardingAgain() } label: {
                    Label(L("Einführung ansehen"), systemImage: "sparkles")
                }
                .accessibilityIdentifier("show-onboarding")
            }
        }
        .navigationTitle(L("Mehr"))
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editingGoal = false
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section(L("Sprache")) {
                Picker(L("Sprache"), selection: Binding(get: { model.preferences.language }, set: { model.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section(L("Anpassen")) {
                Toggle(L("Meldo anzeigen"), isOn: Binding(get: { model.preferences.showMascot }, set: { model.setShowMascot($0) }))
                Toggle(L("Haptisches Feedback"), isOn: Binding(get: { model.preferences.haptics }, set: { model.setHaptics($0) }))
                NavigationLink { DashboardCardsView() } label: {
                    Label(L("Startseite anpassen"), systemImage: "rectangle.3.group")
                }
                NavigationLink { AppIconPicker() } label: {
                    Label(L("App-Symbol"), systemImage: "app.badge")
                }
                NavigationLink { BarSettingsView() } label: {
                    Label(L("Leiste und Startseite"), systemImage: "dock.rectangle")
                }
            }
            Section(L("Design")) {
                Picker(L("Darstellung"), selection: Binding(get: { model.preferences.appearance }, set: { model.setAppearance($0) })) {
                    ForEach(AppearanceChoice.allCases) { Text($0.localizedName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle(L("A/B-Wochen verwenden"), isOn: Binding(
                    get: { model.preferences.weekAReference != nil },
                    set: { model.setWeekAReference($0 ? model.currentDate : nil) }
                ))
                if model.preferences.weekAReference != nil {
                    Picker(L("Diese Woche ist"), selection: Binding(
                        get: { model.isWeekA(model.currentDate) },
                        set: { model.setCurrentWeekIsA($0) }
                    )) {
                        Text(L("A-Woche")).tag(true)
                        Text(L("B-Woche")).tag(false)
                    }
                }
            } header: {
                Text(L("Stundenplan"))
            } footer: {
                Text(L("Für Stunden, die nur jede zweite Woche stattfinden."))
            }
            Section(L("Melde Tracker")) {
                Button {
                    editingGoal = true
                } label: {
                    LabeledContent(L("Wochenziel"), value: model.preferences.weeklyGoal.map { "\($0)" } ?? L("Keins"))
                }
                .foregroundStyle(.primary)
            }
            Section {
                Toggle(L("Nach jeder Stunde nachfragen"), isOn: Binding(
                    get: { model.preferences.askAfterLesson },
                    set: { on in
                        guard on else { return model.setAskAfterLesson(false) }
                        Task {
                            let allowed = await Reminders.requestAuthorization()
                            notificationsDenied = !allowed
                            model.setAskAfterLesson(allowed)
                        }
                    }
                ))
                Toggle(L("Live-Aktivität während der Stunde"), isOn: Binding(
                    get: { model.preferences.liveActivities },
                    set: { model.setLiveActivities($0) }
                ))
            } header: {
                Text(L("Mitteilungen"))
            } footer: {
                if notificationsDenied {
                    Text(L("Mitteilungen sind aus. Erlaube sie in den Einstellungen, damit Erinnerungen ankommen."))
                } else {
                    Text(L("Fragt kurz nach dem Klingeln „Hast du dich gemeldet?“. Antworte direkt in der Mitteilung. Stunden mit Meldung werden übersprungen."))
                }
            }
            Section {
                Toggle(L("Microsoft Teams"), isOn: Binding(get: { model.preferences.teamsEnabled }, set: { model.setTeamsEnabled($0) }))
            } header: {
                Text(L("Erweitert"))
            } footer: {
                Text(L("Schalte das nur ein, wenn deine Schule Meldo für Teams freigegeben hat. Viele Schulen müssen das erst erlauben."))
            }
            if !model.isSharedWithWidgets {
                Section(L("Widgets")) {
                    Label(L("Widgets und der Melden-Knopf brauchen eine App-Gruppe. Installiere Meldo mit AltStore, damit sie deine Daten sehen."), systemImage: "info.circle")
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle(L("Einstellungen"))
        .sheet(isPresented: $editingGoal) { WeeklyGoalSheet(now: model.currentDate) }
    }
}

struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                LabeledContent(L("Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("Unbekannt"))
                LabeledContent(L("Rust-Kern"), value: coreVersion())
                // The iPad has no Mehr tab; the tour is reopened from here.
                Button(L("Einführung ansehen")) { model.showOnboardingAgain() }
            }
            Section(L("Datenschutz")) {
                Text(L("Deine Daten bleiben auf deinem Gerät. Meldo hat keinen eigenen Server, keine Werbung und kein Tracking."))
                    .font(.subheadline)
                NavigationLink(L("Datenschutzerklärung")) { PrivacyPolicyView() }
            }
            Section(L("Hinweis")) {
                Text(L("Meldo zählt deine Beteiligung und berechnet Durchschnitte. Offizielle Noten vergibt allein deine Schule."))
                    .font(.subheadline)
            }
        }
        .navigationTitle(L("Über Meldo"))
    }
}

/// The Start cards as a list: show, hide, sort and size them. Same layout as
/// "Anpassen" on the Start screen, easier with VoiceOver.
struct DashboardCardsView: View {
    @Environment(AppModel.self) private var model

    private var layout: [CardSlot<DashboardCard>] { model.preferences.homeLayout }

    private var hidden: [DashboardCard] {
        DashboardCard.allCases.filter { kind in !layout.contains { $0.kind == kind } }
    }

    var body: some View {
        List {
            Section {
                ForEach(layout, id: \.kind) { slot in
                    HStack {
                        Label(DashboardView.title(slot.kind), systemImage: DashboardView.symbol(slot.kind))
                        Spacer()
                        Picker(L("Größe"), selection: Binding(
                            get: { slot.size },
                            set: { size in
                                var list = layout
                                if let i = list.firstIndex(where: { $0.kind == slot.kind }) { list[i].size = size }
                                model.setHomeLayout(list)
                            }
                        )) {
                            ForEach(CardSize.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                .onMove { from, to in
                    var list = layout
                    list.move(fromOffsets: from, toOffset: to)
                    model.setHomeLayout(list)
                }
                .onDelete { offsets in
                    var list = layout
                    list.remove(atOffsets: offsets)
                    model.setHomeLayout(list)
                }
            } header: {
                Text(L("Sichtbar"))
            } footer: {
                Text(L("Ziehen zum Sortieren. Tipp: Auf der Startseite kannst du Karten auch mit „Anpassen“ verschieben."))
            }
            if !hidden.isEmpty {
                Section(L("Ausgeblendet")) {
                    ForEach(hidden) { kind in
                        Button {
                            model.setHomeLayout(layout + [CardSlot(kind: kind, size: .medium)])
                        } label: {
                            Label(DashboardView.title(kind), systemImage: DashboardView.symbol(kind))
                        }
                    }
                }
            }
            Section {
                Button(L("Standard wiederherstellen")) {
                    model.setHomeLayout(CardSlot<DashboardCard>.defaultHome)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(L("Startseite anpassen"))
    }
}

/// Alternate app icons, rendered from the same Meldo artwork.
struct AppIconPicker: View {
    @Environment(AppModel.self) private var model
    @State private var problem: String?

    var body: some View {
        List {
            ForEach(AppIconChoice.allCases) { choice in
                Button {
                    Task { await apply(choice) }
                } label: {
                    HStack {
                        Text(Self.title(choice)).foregroundStyle(.primary)
                        Spacer()
                        if model.preferences.appIcon == choice {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
        }
        .navigationTitle(L("App-Symbol"))
    }

    private func apply(_ choice: AppIconChoice) async {
        guard UIApplication.shared.supportsAlternateIcons else {
            problem = L("Dieses Gerät unterstützt keine anderen App-Symbole.")
            return
        }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.assetName)
            model.setAppIcon(choice)
            problem = nil
        } catch {
            problem = L("Das App-Symbol konnte nicht geändert werden.")
        }
    }

    static func title(_ choice: AppIconChoice) -> String {
        switch choice {
        case .standard: L("Indigo (Standard)")
        case .orange: L("Orange")
        case .night: L("Nacht")
        }
    }
}

/// Which two places sit in the tab bar after Start and Stundenplan, and which screen
/// Meldo opens on. The rest is under Mehr (iPad: in the sidebar).
struct BarSettingsView: View {
    @Environment(AppModel.self) private var model

    private var slots: [AppTab] { AppTab.barSlots(model.preferences) }

    var body: some View {
        Form {
            Section {
                slotPicker(L("Dritter Platz"), index: 0)
                slotPicker(L("Vierter Platz"), index: 1)
            } header: {
                Text(L("Leiste"))
            } footer: {
                Text(L("Start und Stundenplan bleiben immer in der Leiste. Alles andere findest du unter Mehr."))
            }
            Section {
                Picker(L("Beim Öffnen"), selection: Binding(get: { startTab }, set: { model.setStartTab($0.rawValue) })) {
                    ForEach([AppTab.home, .timetable] + slots, id: \.self) { place in
                        Label(place.title, systemImage: place.symbol).tag(place)
                    }
                }
            } header: {
                Text(L("Startseite"))
            } footer: {
                Text(L("Diese Seite zeigt Meldo, wenn du die App öffnest."))
            }
        }
        .navigationTitle(L("Leiste und Startseite"))
    }

    /// The opening screen, or Start if the chosen one left the bar.
    private var startTab: AppTab {
        let chosen = AppTab(rawValue: model.preferences.startTab) ?? .home
        return ([.home, .timetable] + slots).contains(chosen) ? chosen : .home
    }

    private func slotPicker(_ title: String, index: Int) -> some View {
        Picker(title, selection: Binding(get: { slots[index] }, set: { place in
            var next = slots
            // Choosing what the other place shows swaps the two.
            if let other = next.firstIndex(of: place), other != index { next.swapAt(other, index) } else { next[index] = place }
            model.setBarTabs(next.map(\.rawValue))
        })) {
            ForEach(AppTab.barChoices, id: \.self) { place in
                Label(place.title, systemImage: place.symbol).tag(place)
            }
        }
    }
}
