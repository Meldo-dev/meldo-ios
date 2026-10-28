import AppIntents
import Foundation

/// One tap from a widget, the Control Center, the Lock Screen or the Live
/// Activity: records a Meldung for the current lesson. Outside lessons it is
/// logged without a subject, and the app offers to assign it later.
///
/// `LiveActivityIntent` makes the system run it in the app's process, so it
/// can also start or update the lesson's Live Activity.
nonisolated struct LogParticipationIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Melden"
    static let description = IntentDescription("Erfasst eine Meldung für die laufende Stunde.")
    static let supportedModes: IntentModes = .background

    /// Taps closer together than this count once.
    static let doubleTap: TimeInterval = 2

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let calendar = Calendar.current
        let now = Date()
        guard let store = LocalStore.sharedIfAvailable() ?? (try? LocalStore.standard()) else {
            return .result(dialog: "\(L("Öffne Meldo einmal, damit Melden hier funktioniert."))")
        }
        var entry: ParticipationEntry?
        var duplicate = false
        let data = try store.update { data in
            // A double tap on a widget, the Control or the Live Activity is one Meldung, not two.
            // A Meldung "from the future" (clock changed, another device) is no double tap.
            if data.participation.contains(where: { (0..<Self.doubleTap).contains(now.timeIntervalSince($0.recordedAt)) }) {
                duplicate = true
                return
            }
            if let recorded = MeldeEngine.recordForLesson(in: &data, at: now, calendar: calendar) {
                entry = recorded
            } else {
                data.participation.append(ParticipationEntry(subjectID: nil, lessonID: nil, recordedAt: now))
            }
        }
        Localization.apply(data.preferences.language)
        if duplicate { return .result(dialog: "\(L("Schon gemeldet."))") }
        Surfaces.reload()
        if let entry {
            LessonCheckIns.didRecord(entry, calendar: calendar)
            await LessonActivity.refresh(data, at: now, calendar: calendar)
            let name = data.subjects.first { $0.id == entry.subjectID }?.name ?? L("Unterricht")
            return .result(dialog: "\(L("Gemeldet in \(name)."))")
        }
        return .result(dialog: "\(L("Gemeldet, ohne Fach. Ordne es in der App zu."))")
    }
}
