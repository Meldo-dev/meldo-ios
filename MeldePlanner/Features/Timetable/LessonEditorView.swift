import MeldeCore
import SwiftUI

/// Create or edit a lesson. Overlaps are detected by the Rust core before saving.
struct LessonEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let original: Lesson?
    @State private var draft: Lesson
    @State private var problem: String?
    @State private var confirmingDelete = false

    init(lesson: Lesson?, weekday: Int) {
        original = lesson
        _draft = State(initialValue: lesson ?? Lesson(
            subjectID: UUID(), weekday: weekday, startMinute: 8 * 60, endMinute: 8 * 60 + 45
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Fach"), selection: $draft.subjectID) {
                        ForEach(model.subjects) { subject in
                            Label(subject.name, systemImage: subject.symbolName).tag(subject.id)
                        }
                    }
                    Picker(L("Tag"), selection: $draft.weekday) {
                        ForEach(0..<7, id: \.self) { Text(WeekdayText.full($0)).tag($0) }
                    }
                }
                Section {
                    DatePicker(L("Beginn"), selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker(L("Ende"), selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                }
                Section {
                    TextField(L("Raum"), text: $draft.room)
                    Picker(L("Woche"), selection: $draft.parity) {
                        Text(L("Jede Woche")).tag(WeekParity.every)
                        Text(L("Nur A-Woche")).tag(WeekParity.a)
                        Text(L("Nur B-Woche")).tag(WeekParity.b)
                    }
                } footer: {
                    if draft.parity != .every && model.preferences.weekAReference == nil {
                        Text(L("Lege in den Einstellungen fest, welche Woche eine A-Woche ist. Bis dahin findet die Stunde jede Woche statt."))
                    }
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if original != nil {
                    Section {
                        Button(L("Stunde löschen"), role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? L("Neue Stunde") : L("Stunde bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern"), action: save)
                        .disabled(model.subject(draft.subjectID) == nil)
                }
            }
            .confirmationDialog(L("Stunde löschen?"), isPresented: $confirmingDelete) {
                Button(L("Löschen"), role: .destructive) {
                    if let original { model.deleteLesson(original.id) }
                    dismiss()
                }
            }
            .onAppear {
                if model.subject(draft.subjectID) == nil, let first = model.subjects.first {
                    draft.subjectID = first.id
                }
            }
        }
    }

    private func save() {
        guard draft.endMinute > draft.startMinute else {
            problem = L("Das Ende muss nach dem Beginn liegen.")
            return
        }
        let issues = model.save(draft)
        if issues.isEmpty {
            dismiss()
        } else {
            problem = describe(issues)
        }
    }

    private func describe(_ issues: [FfiTimetableIssue]) -> String {
        for issue in issues {
            if case .overlap(let first, let second) = issue {
                let otherID = first == draft.id.uuidString ? second : first
                let other = model.lessons.first { $0.id.uuidString == otherID }
                let name = other.flatMap { model.subject($0.subjectID)?.name } ?? L("Unbekannt")
                return L("Überschneidet sich mit \(name).")
            }
        }
        return L("Diese Stunde ist ungültig.")
    }

    /// Bridges minutes since midnight to the DatePicker's `Date`.
    private func minuteBinding(_ keyPath: WritableKeyPath<Lesson, Int>) -> Binding<Date> {
        let calendar = model.calendar
        let midnight = calendar.startOfDay(for: .now)
        return Binding {
            // Wall-clock time, not seconds since midnight: DST days are 23 or 25 hours long.
            let minutes = draft[keyPath: keyPath]
            return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: midnight) ?? midnight
        } set: { date in
            let c = calendar.dateComponents([.hour, .minute], from: date)
            draft[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            problem = nil
        }
    }
}
