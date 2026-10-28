import MeldeCore
import SwiftUI

/// Hausaufgaben and to-dos grouped by urgency (grouping comes from the Rust core).
struct TaskListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var filter: TaskKind? = nil
    @State private var editing: SchoolTask?
    @State private var creating = false

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let sections = model.taskSections(today: model.currentDate, kind: filter)
            // iPad keeps the board even when a filter is empty, so the filter doesn't move.
            if sizeClass == .regular {
                TaskBoard(sections: sections, today: model.currentDate, filter: $filter) { editing = $0 }
            } else {
            List {
                Section {
                    Picker(L("Anzeigen"), selection: $filter) {
                        Text(L("Alle")).tag(TaskKind?.none)
                        Text(L("Hausaufgaben")).tag(TaskKind?.some(.homework))
                        Text(L("To-dos")).tag(TaskKind?.some(.todo))
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if sections.isEmpty {
                    ContentUnavailableView {
                        Label(L("Nichts zu tun"), systemImage: "checkmark.circle")
                    } description: {
                        Text(L("Trag Hausaufgaben direkt im Stundenplan ein: lange auf eine Stunde drücken."))
                    } actions: {
                        Button(L("Aufgabe hinzufügen")) { creating = true }
                            .buttonStyle(.glassProminent)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(sections) { section in
                    Section(Self.title(for: section.group)) {
                        ForEach(section.tasks) { task in
                            TaskRow(task: task, today: model.currentDate) { editing = task }
                                .swipeActions {
                                    Button(L("Löschen"), systemImage: "trash", role: .destructive) {
                                        model.deleteTask(task.id)
                                    }
                                }
                        }
                    }
                }
            }
            .animation(.default, value: model.tasks)
            }
        }
        .navigationTitle(L("Aufgaben"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Aufgabe hinzufügen"), systemImage: "plus") { creating = true }
            }
        }
        .sheet(item: $editing) { TaskEditorView(task: $0) }
        .sheet(isPresented: $creating) { TaskEditorView(task: nil, kind: filter ?? .homework) }
    }

    static func title(for group: FfiTaskGroup) -> String {
        switch group {
        case .overdue: L("Überfällig")
        case .today: L("Heute")
        case .tomorrow: L("Morgen")
        case .thisWeek: L("Diese Woche")
        case .later: L("Später")
        case .noDate: L("Ohne Datum")
        case .completed: L("Erledigt")
        }
    }
}

/// iPad: tasks as a board with three columns (now, soon, later) and the done
/// tasks below, so a whole week fits on screen without scrolling a long list.
private struct TaskBoard: View {
    @Environment(AppModel.self) private var model
    let sections: [AppModel.TaskSection]
    let today: Date
    @Binding var filter: TaskKind?
    var onOpen: (SchoolTask) -> Void

    private let columns: [(title: String, symbol: String, groups: [FfiTaskGroup])] = [
        (L("Jetzt"), "exclamationmark.circle", [.overdue, .today]),
        (L("Bald"), "calendar", [.tomorrow, .thisWeek]),
        (L("Später"), "tray", [.later, .noDate]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.spacingL) {
                Picker(L("Anzeigen"), selection: $filter) {
                    Text(L("Alle")).tag(TaskKind?.none)
                    Text(L("Hausaufgaben")).tag(TaskKind?.some(.homework))
                    Text(L("To-dos")).tag(TaskKind?.some(.todo))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                HStack(alignment: .top, spacing: DS.spacingL) {
                    ForEach(columns, id: \.title) { column in
                        let tasks = column.groups.flatMap { group in
                            sections.first { $0.group == group }?.tasks ?? []
                        }
                        Card(title: column.title, systemImage: column.symbol) {
                            if tasks.isEmpty {
                                Text(L("Nichts zu tun")).foregroundStyle(.secondary)
                            }
                            ForEach(tasks) { task in
                                TaskRow(task: task, today: today) { onOpen(task) }
                                    .contextMenu {
                                        Button(L("Löschen"), systemImage: "trash", role: .destructive) {
                                            model.deleteTask(task.id)
                                        }
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                if let done = sections.first(where: { $0.group == .completed }), !done.tasks.isEmpty {
                    Card(title: L("Erledigt"), systemImage: "checkmark.circle") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DS.spacingM)], alignment: .leading) {
                            ForEach(done.tasks.prefix(30)) { task in
                                TaskRow(task: task, today: today) { onOpen(task) }
                            }
                        }
                    }
                }
            }
            .padding(DS.spacingL)
        }
        .background(ThemedBackground())
        .animation(.default, value: model.tasks)
    }
}

/// One task with a check circle. Checking off gives haptic feedback.
struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: SchoolTask
    let today: Date
    var onOpen: () -> Void

    @State private var checks = 0

    var body: some View {
        let subject = model.subject(task.subjectID)
        HStack(spacing: DS.spacingM) {
            Button {
                checks += 1
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? Color.green : (subject?.color.color ?? Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? L("Als offen markieren") : L("Als erledigt markieren"))
            .sensoryFeedback(.success, trigger: checks) { _, _ in model.preferences.haptics }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .strikethrough(task.isDone)
                    HStack(spacing: DS.spacingS) {
                        if let subject {
                            Text(subject.name).foregroundStyle(subject.color.color)
                        }
                        if let due = task.dueDate {
                            Text(DueText.label(due, today: today, calendar: model.calendar))
                                .foregroundStyle(!task.isDone && due < model.calendar.startOfDay(for: today) ? Color.red : Color.secondary)
                        }
                        if task.recurrence != .never {
                            Image(systemName: "repeat").accessibilityLabel(L("Wiederholt sich"))
                        }
                        if task.reminderAt != nil, !task.isDone {
                            Image(systemName: "bell").accessibilityLabel(L("Erinnerung"))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if task.priority == .high, !task.isDone {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(L("Wichtig"))
            }
        }
    }
}

enum DueText {
    static func label(_ due: Date, today: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return L("heute")
        case 1: return L("morgen")
        case -1: return L("gestern")
        case 2...6: return due.formatted(.dateTime.weekday(.wide).locale(Localization.locale))
        default: return due.formatted(.dateTime.day().month(.abbreviated).locale(Localization.locale))
        }
    }
}
