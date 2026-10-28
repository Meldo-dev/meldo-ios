import SwiftUI

/// Melden on Start and Stundenplan (iPhone tab accessory, iPad floating). One tap records a
/// Meldung for the current lesson (the button shows this lesson's count);
/// outside lessons it suggests the likely lesson instead of listing every
/// subject. After recording it shows the subject with Undo for a few seconds.
struct MeldenButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var lastEntry: ParticipationEntry?
    @State private var choosingSubject = false
    /// Parallel courses to pick from (subject ids) when Melden can't tell which one runs.
    @State private var courseOptions: [UUID] = []
    @State private var successCount = 0

    /// `true` in the iPhone tab bar's bottom accessory: a full-width row on the
    /// accessory's own glass instead of a floating capsule over the content.
    var inAccessory = false

    var body: some View {
        Group {
            if inAccessory {
                HStack(spacing: 0) {
                    Button(action: record) { buttonLabel.frame(maxWidth: .infinity) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .contentShape(.rect)
                        .modifier(MeldenAccessibility(count: lessonCount, undo: lastEntry.map { entry in { undo(entry) } }))
                    if let entry = lastEntry {
                        Divider().frame(height: 22)
                        Button(L("Rückgängig"), systemImage: "arrow.uturn.backward") { undo(entry) }
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .frame(width: 52)
                            .contentShape(.rect)
                            .buttonStyle(.plain)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, DS.spacingS)
            } else {
                HStack(spacing: DS.spacingS) {
                    if let entry = lastEntry {
                        Button {
                            undo(entry)
                        } label: {
                            Label(L("Rückgängig"), systemImage: "arrow.uturn.backward")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, DS.spacingM)
                                .padding(.vertical, DS.spacingS)
                        }
                        .buttonStyle(.glass)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    }
                    Button(action: record) {
                        buttonLabel
                            .padding(.horizontal, DS.spacingL)
                            .padding(.vertical, DS.spacingM)
                    }
                    .buttonStyle(.glassProminent)
                    .modifier(MeldenAccessibility(count: lessonCount, undo: lastEntry.map { entry in { undo(entry) } }))
                }
                .padding(DS.spacingL)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.3), value: lastEntry?.id)
        .sensoryFeedback(.success, trigger: successCount) { _, _ in model.preferences.haptics }
        .task(id: lastEntry?.id) {
            guard lastEntry != nil else { return }
            // Long enough to notice after a glance down; with VoiceOver it stays until the next action.
            guard !voiceOver else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { lastEntry = nil }
        }
        // Asked once per parallel slot; the answer counts for every week.
        .confirmationDialog(L("Welcher Kurs ist deiner?"), isPresented: Binding(get: { !courseOptions.isEmpty }, set: { if !$0 { courseOptions = [] } }), titleVisibility: .visible) {
            let options = courseOptions
            ForEach(options, id: \.self) { id in
                Button(model.subject(id)?.name ?? L("Unbekanntes Fach")) { choose(id, among: options) }
            }
        } message: {
            Text(L("Meldo zeigt deinen Kurs ab jetzt jede Woche zu dieser Zeit."))
        }
        .sheet(isPresented: $choosingSubject) {
            SubjectPickerSheet { subjectID in
                lastEntry = model.recordParticipation(subjectID: subjectID)
                successCount += 1
                announce()
            }
        }
    }

    private var buttonLabel: some View {
        HStack(spacing: DS.spacingS) {
            Label(label, systemImage: lastEntry == nil ? "hand.raised.fill" : "checkmark")
                .contentTransition(.symbolEffect(.replace))
            // This lesson's count inside the button: a corner badge read like unread notifications.
            let count = lessonCount
            if count > 0 {
                Text("\(count)×")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(inAccessory ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.25), in: .capsule)
                    .accessibilityHidden(true)
            }
        }
        .font(.headline)
    }

    /// Meldungen in the running lesson today.
    private var lessonCount: Int {
        guard let current = model.currentLesson(at: model.currentDate) else { return 0 }
        return MeldeEngine.count(model.data, lessonID: current.lessonId, on: model.currentDate, calendar: model.calendar)
    }

    private var label: String {
        guard let entry = lastEntry else { return L("Melden") }
        return model.subject(entry.subjectID)?.name ?? L("Gemeldet")
    }

    private func undo(_ entry: ParticipationEntry) {
        model.deleteParticipation(entry.id)
        lastEntry = nil
    }

    /// VoiceOver hears which lesson got the Meldung without finding the button again.
    private func announce() {
        AccessibilityNotification.Announcement(L("Gemeldet: \(label)")).post()
    }

    private func record() {
        switch model.recordParticipation() {
        case .recorded(let entry):
            lastEntry = entry
            successCount += 1
            announce()
        case .needsSubject:
            choosingSubject = true
        case .needsCourse(let options):
            courseOptions = options
        }
    }

    private func choose(_ subjectID: UUID, among options: [UUID]) {
        if case .recorded(let entry) = model.recordParticipation(choosingCourse: subjectID, among: options) {
            lastEntry = entry
            successCount += 1
            announce()
        }
    }
}

/// VoiceOver for both Melden layouts: what it does, this lesson's count, and Undo as an action.
private struct MeldenAccessibility: ViewModifier {
    let count: Int
    let undo: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(L("Meldung erfassen"))
            .accessibilityValue(count > 0 ? L("\(count)× in dieser Stunde") : "")
            .accessibilityActions {
                if let undo {
                    Button(L("Rückgängig"), action: undo)
                }
            }
            .keyboardShortcut("m", modifiers: .command)
    }
}

/// Outside a lesson: the lesson that just ended, the next one and the
/// subjects used most, as big buttons. Every subject stays one tap away.
struct SubjectPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onPick: (UUID?) -> Void
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

    var body: some View {
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
