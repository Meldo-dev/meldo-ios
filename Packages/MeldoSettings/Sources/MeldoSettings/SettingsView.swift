import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.features) private var features
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
            // Sections the features add (Microsoft Teams under Erweitert).
            ForEach(features.all.indices, id: \.self) { i in
                features.all[i].settingsSection?()
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
    @Environment(\.features) private var features

    /// The cards this build has, in the student's order (cards of features left out stay saved).
    private var layout: [CardSlot<DashboardCard>] {
        model.preferences.homeLayout.filter { features.dashboardCard($0.kind) != nil }
    }

    private var hidden: [DashboardCard] {
        features.dashboardCards.map(\.kind).filter { kind in !layout.contains { $0.kind == kind } }
    }

    /// Saves the visible list and keeps the slots of cards this build doesn't have.
    private func save(_ list: [CardSlot<DashboardCard>]) {
        model.setHomeLayout(list + model.preferences.homeLayout.filter { features.dashboardCard($0.kind) == nil })
    }

    private func title(_ kind: DashboardCard) -> String { features.dashboardCard(kind)?.title() ?? "" }
    private func symbol(_ kind: DashboardCard) -> String { features.dashboardCard(kind)?.symbol ?? "square" }

    var body: some View {
        List {
            Section {
                ForEach(layout, id: \.kind) { slot in
                    HStack {
                        Label(title(slot.kind), systemImage: symbol(slot.kind))
                        Spacer()
                        Picker(L("Größe"), selection: Binding(
                            get: { slot.size },
                            set: { size in
                                var list = layout
                                if let i = list.firstIndex(where: { $0.kind == slot.kind }) { list[i].size = size }
                                save(list)
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
                    save(list)
                }
                .onDelete { offsets in
                    var list = layout
                    list.remove(atOffsets: offsets)
                    save(list)
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
                            save(layout + [CardSlot(kind: kind, size: .medium)])
                        } label: {
                            Label(title(kind), systemImage: symbol(kind))
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

/// Which two places sit in the tab bar after the pinned tabs, and which screen
/// Meldo opens on. The rest is under Mehr (iPad: in the sidebar).
struct BarSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.features) private var features

    private var slots: [MeldoFeature] { features.barSlots(model.preferences) }
    private var opening: [MeldoFeature] { features.placed(.pinned) + slots }

    var body: some View {
        Form {
            if slots.count == 2 {
                Section {
                    slotPicker(L("Dritter Platz"), index: 0)
                    slotPicker(L("Vierter Platz"), index: 1)
                } header: {
                    Text(L("Leiste"))
                } footer: {
                    Text(L("Start und Stundenplan bleiben immer in der Leiste. Alles andere findest du unter Mehr."))
                }
            }
            Section {
                Picker(L("Beim Öffnen"), selection: Binding(get: { startTab }, set: { model.setStartTab($0) })) {
                    ForEach(opening) { place in
                        Label(place.title(), systemImage: place.symbol).tag(place.id)
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

    /// The opening screen, or the first pinned one if the chosen one left the bar.
    private var startTab: String {
        let chosen = model.preferences.startTab
        return opening.contains { $0.id == chosen } ? chosen : (opening.first?.id ?? chosen)
    }

    private func slotPicker(_ title: String, index: Int) -> some View {
        Picker(title, selection: Binding(get: { slots[index].id }, set: { id in
            var next = slots.map(\.id)
            // Choosing what the other place shows swaps the two.
            if let other = next.firstIndex(of: id), other != index { next.swapAt(other, index) } else { next[index] = id }
            model.setBarTabs(next)
        })) {
            ForEach(features.barChoices) { place in
                Label(place.title(), systemImage: place.symbol).tag(place.id)
            }
        }
    }
}
