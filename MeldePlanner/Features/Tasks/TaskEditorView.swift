import SwiftUI

/// Create or edit a Hausaufgabe or to-do.
struct TaskEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: SchoolTask
    @State private var hasDue: Bool
    @State private var hasReminder: Bool
    @State private var notificationsDenied = false

    /// - Parameters:
    ///   - subjectID: preselects the subject and sets the due date to its next lesson.
    init(task: SchoolTask?, kind: TaskKind = .homework, subjectID: UUID? = nil) {
        isNew = task == nil
        let initial = task ?? SchoolTask(title: "", kind: kind, subjectID: subjectID)
        _draft = State(initialValue: initial)
        _hasDue = State(initialValue: task == nil ? kind == .homework : initial.dueDate != nil)
        _hasReminder = State(initialValue: initial.reminderAt != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Was ist zu tun?"), text: $draft.title, axis: .vertical)
                        .font(.headline)
                    Picker(L("Art"), selection: $draft.kind) {
                        Text(L("Hausaufgabe")).tag(TaskKind.homework)
                        Text(L("To-do")).tag(TaskKind.todo)
                    }
                    .pickerStyle(.segmented)
                    Picker(L("Fach"), selection: $draft.subjectID) {
                        Text(L("Kein Fach")).tag(UUID?.none)
                        ForEach(model.subjects) { subject in
                            Label(subject.name, systemImage: subject.symbolName).tag(UUID?.some(subject.id))
                        }
                    }
                }

                Section {
                    Toggle(L("Fällig am"), isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker(L("Datum"), selection: dueBinding, displayedComponents: .date)
                        if let subjectID = draft.subjectID,
                           let nextLesson = model.nextLessonDay(for: subjectID, after: model.currentDate) {
                            Button {
                                draft.dueDate = nextLesson
                            } label: {
                                Label(L("Bis zur nächsten Stunde (\(DueText.label(nextLesson, today: model.currentDate, calendar: model.calendar)))"), systemImage: "calendar.badge.clock")
                            }
                        }
                    }
                    Picker(L("Wiederholen"), selection: $draft.recurrence) {
                        Text(L("Nie")).tag(TaskRecurrence.never)
                        Text(L("Täglich")).tag(TaskRecurrence.daily)
                        Text(L("Schultage (Mo–Fr)")).tag(TaskRecurrence.weekdays)
                        Text(L("Wöchentlich")).tag(TaskRecurrence.weekly)
                        Text(L("Alle zwei Wochen")).tag(TaskRecurrence.biweekly)
                    }
                    Picker(L("Wichtigkeit"), selection: $draft.priority) {
                        Text(L("Niedrig")).tag(TaskPriority.low)
                        Text(L("Normal")).tag(TaskPriority.normal)
                        Text(L("Hoch")).tag(TaskPriority.high)
                    }
                }

                Section {
                    Toggle(L("Erinnerung"), isOn: $hasReminder.animation())
                        .onChange(of: hasReminder) { _, on in
                            guard on else { return }
                            Task {
                                notificationsDenied = !(await Reminders.requestAuthorization())
                            }
                        }
                    if hasReminder {
                        DatePicker(L("Um"), selection: reminderBinding)
                    }
                } footer: {
                    if notificationsDenied {
                        Text(L("Mitteilungen sind aus. Erlaube sie in den Einstellungen, damit Erinnerungen ankommen."))
                    }
                }

                Section(L("Notizen")) {
                    TextField(L("Seite, Aufgabe, Details …"), text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if !isNew {
                    Section {
                        Button(L("Aufgabe löschen"), role: .destructive) {
                            model.deleteTask(draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? L("Neue Aufgabe") : L("Aufgabe bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern"), action: save)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: prefillDue)
        }
    }

    private var dueBinding: Binding<Date> {
        Binding(
            get: { draft.dueDate ?? model.calendar.startOfDay(for: model.currentDate) },
            set: { draft.dueDate = $0 }
        )
    }

    private var reminderBinding: Binding<Date> {
        Binding(
            get: { draft.reminderAt ?? defaultReminder },
            set: { draft.reminderAt = $0 }
        )
    }

    /// 17:00 the day before the due date, or in one hour without one.
    private var defaultReminder: Date {
        let cal = model.calendar
        if let due = draft.dueDate,
           let dayBefore = cal.date(byAdding: .day, value: -1, to: due),
           let evening = cal.date(bySettingHour: 17, minute: 0, second: 0, of: dayBefore),
           evening > model.currentDate {
            return evening
        }
        return model.currentDate.addingTimeInterval(3600)
    }

    private func prefillDue() {
        guard isNew, draft.dueDate == nil, hasDue else { return }
        if let subjectID = draft.subjectID, let next = model.nextLessonDay(for: subjectID, after: model.currentDate) {
            draft.dueDate = next
        } else {
            draft.dueDate = model.calendar.date(byAdding: .day, value: 1, to: model.calendar.startOfDay(for: model.currentDate))
        }
    }

    private func save() {
        var task = draft
        if !hasDue { task.dueDate = nil }
        task.reminderAt = hasReminder ? (draft.reminderAt ?? defaultReminder) : nil
        model.upsert(task)
        dismiss()
    }
}
