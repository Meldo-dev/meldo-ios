import MeldoKit
import MeldoState
import SwiftUI

/// Outside a lesson: the lesson that just ended, the next one and the
/// subjects used most, as big buttons. Every subject stays one tap away.
public struct SubjectPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    public var onPick: (UUID?) -> Void

    public init(onPick: @escaping (UUID?) -> Void) {
        self.onPick = onPick
    }
    @State private var showingAll = false

    private struct Suggestion: Identifiable {
        let subject: Subject
        let reason: String
        var id: UUID { subject.id }
    }

    private var suggestions: [Suggestion] {
        let now = model.currentDate
        let minute = model.calendar.component(.hour, from: now) * 60 + model.calendar.component(.minute, from: now)
        let blocks = model.timetableBlocks(on: now).filter { $0.kind != .cancelled }
        var list: [Suggestion] = []
        func add(_ id: UUID?, _ reason: String) {
            guard let id, let subject = model.subject(id), !list.contains(where: { $0.subject.id == id }) else { return }
            list.append(Suggestion(subject: subject, reason: reason))
        }
        if let ended = blocks.last(where: { $0.endMinute <= minute && minute - $0.endMinute <= 90 }) {
            add(ended.subjectID, L("Gerade vorbei"))
        }
        if let next = blocks.first(where: { $0.startMinute > minute }) {
            add(next.subjectID, L("Als Nächstes"))
        }
        // Today's earlier lessons, latest first, with their time: more telling than a count.
        for block in blocks.filter({ $0.endMinute <= minute }).reversed() {
            add(block.subjectID, L("Heute \(TimeText.clock(block.startMinute))"))
        }
        let counts = Dictionary(grouping: model.data.participation.compactMap(\.subjectID), by: { $0 }).mapValues(\.count)
        for (id, _) in counts.sorted(by: { $0.value > $1.value }).prefix(4) {
            add(id, L("Oft gemeldet"))
        }
        return Array(list.prefix(4))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.spacingM) {
                    if model.subjects.isEmpty {
                        Text(L("Lege zuerst Fächer an, damit Meldungen zugeordnet werden können."))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L("Gerade läuft keine Stunde. Wofür war die Meldung?"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.spacingS), GridItem(.flexible())], spacing: DS.spacingS) {
                            ForEach(suggestions) { suggestion in
                                Button { pick(suggestion.subject.id) } label: {
                                    VStack(alignment: .leading, spacing: DS.spacingS) {
                                        SubjectIcon(subject: suggestion.subject, size: 32)
                                        Text(suggestion.subject.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(suggestion.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(DS.spacingM)
                                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.rowRadius))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        DisclosureGroup(L("Anderes Fach"), isExpanded: $showingAll) {
                            VStack(spacing: 0) {
                                ForEach(model.subjects) { subject in
                                    Button { pick(subject.id) } label: {
                                        HStack(spacing: DS.spacingM) {
                                            SubjectIcon(subject: subject, size: 26)
                                            Text(subject.name).foregroundStyle(.primary)
                                            Spacer()
                                        }
                                        .padding(.vertical, DS.spacingS)
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                        .padding(.top, DS.spacingS)
                    }
                    Button(L("Ohne Fach erfassen")) { pick(nil) }
                        .font(.subheadline)
                        .padding(.top, DS.spacingS)
                }
                .padding(DS.spacingL)
            }
            .navigationTitle(L("Melden"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func pick(_ id: UUID?) {
        onPick(id)
        dismiss()
    }
}

public struct WeeklyGoalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    public var now: Date

    public init(now: Date) {
        self.now = now
    }
    @State private var goal = 10

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goal, in: 1...200) {
                        Text(L("\(goal) Meldungen pro Woche"))
                    }
                } footer: {
                    if let suggestion = model.suggestedWeeklyGoal(asOf: now) {
                        Text(L("Vorschlag aus deinen letzten Wochen: \(suggestion)"))
                    } else {
                        Text(L("Nach einer Woche mit Meldungen schlagen wir dir ein realistisches Ziel vor."))
                    }
                }
                if let suggestion = model.suggestedWeeklyGoal(asOf: now), suggestion != goal {
                    Button(L("Vorschlag übernehmen")) { goal = suggestion }
                }
                if model.preferences.weeklyGoal != nil {
                    Button(L("Ziel entfernen"), role: .destructive) {
                        model.setWeeklyGoal(nil)
                        dismiss()
                    }
                }
            }
            .navigationTitle(L("Wochenziel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern")) {
                        model.setWeeklyGoal(goal)
                        dismiss()
                    }
                }
            }
            .onAppear {
                goal = model.preferences.weeklyGoal ?? model.suggestedWeeklyGoal(asOf: now) ?? 10
            }
        }
        .presentationDetents([.medium])
    }
}

/// Banner for the timetable and calendar: "Herbstferien · 19.10.–01.11.".
public struct HolidayBanner: View {
    public let holiday: Holiday

    public init(holiday: Holiday) {
        self.holiday = holiday
    }

    public var body: some View {
        HStack(spacing: DS.spacingM) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(holiday.name).font(.headline)
                Text(HolidayText.range(holiday))
                    .font(.subheadline)
                    .monospacedDigit()
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(DS.spacingM)
        // Blue like WebUntis, so holidays look the same everywhere.
        .background(Color.untisHoliday, in: .rect(cornerRadius: DS.rowRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
