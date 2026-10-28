import ActivityKit
import Foundation
import MeldeCore

/// Live Activity shown on the Lock Screen (and Dynamic Island) during a lesson:
/// subject, time left and how often you raised your hand, with a Melden button.
nonisolated struct LessonActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Meldungen in this lesson so far.
        var count: Int
        var weekTotal: Int
    }

    var lessonID: String
    var subjectName: String
    var colorKey: String
    var symbolName: String
    var start: Date
    var end: Date
}

/// Starting is only possible while the app (or one of its intents) runs: remote
/// "push to start" would need the paid developer program.
nonisolated enum LessonActivity {
    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Shows the current lesson, or else the next lesson later today, as a Live
    /// Activity (counting down to its start, then to its end), and ends
    /// activities of lessons that are over. Called whenever the app becomes
    /// active and after every Meldung, so the activity moves on to the next lesson.
    static func refresh(_ data: AppData, at now: Date = Date(), calendar: Calendar = .current) async {
        let current = MeldeEngine.currentLesson(data, at: now, calendar: calendar)
            ?? MeldeEngine.nextLesson(data, after: now, calendar: calendar).flatMap { next in
                next.date.date(in: calendar).map { calendar.isDate($0, inSameDayAs: now) } == true ? next : nil
            }
        for activity in Activity<LessonActivityAttributes>.activities
        where !activity.attributes.lessonID.hasPrefix("preview-")
            && (activity.attributes.lessonID != current?.lessonId || activity.attributes.end <= now) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard data.preferences.liveActivities, isAvailable, let current else { return }
        let state = LessonActivityAttributes.ContentState(
            count: MeldeEngine.count(data, lessonID: current.lessonId, on: now, calendar: calendar),
            weekTotal: Int(MeldeEngine.weekSummary(data, containing: now, calendar: calendar)?.total ?? 0)
        )
        let day = calendar.startOfDay(for: now)
        guard let start = calendar.date(minuteOfDay: Int(current.startMinute), on: day),
              let end = calendar.date(minuteOfDay: Int(current.endMinute), on: day) else { return }
        let content = ActivityContent(state: state, staleDate: end)
        if let running = Activity<LessonActivityAttributes>.activities.first(where: { $0.attributes.lessonID == current.lessonId }) {
            await running.update(content)
            return
        }
        let subject = MeldeEngine.subject(data, id: current.subjectId)
        let attributes = LessonActivityAttributes(
            lessonID: current.lessonId,
            subjectName: subject?.name ?? L("Unterricht"),
            colorKey: subject?.color.rawValue ?? SubjectColor.blue.rawValue,
            symbolName: subject?.symbolName ?? "book.closed",
            start: start,
            end: end
        )
        _ = try? Activity<LessonActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
    }
}

extension LessonActivity {
    enum PreviewResult {
        case shown
        case disabledInSettings
        case noLessons
        case failed(String)
    }

    /// Shows the current or next lesson as a Live Activity for two minutes, so
    /// students can see it without waiting for a lesson.
    static func preview(_ data: AppData, at now: Date = Date(), calendar: Calendar = .current) async -> PreviewResult {
        guard isAvailable else { return .disabledInSettings }
        guard let lesson = MeldeEngine.currentLesson(data, at: now, calendar: calendar)
                ?? MeldeEngine.nextLesson(data, after: now, calendar: calendar),
              let day = lesson.date.date(in: calendar),
              let start = calendar.date(minuteOfDay: Int(lesson.startMinute), on: day),
              let end = calendar.date(minuteOfDay: Int(lesson.endMinute), on: day)
        else { return .noLessons }
        let subject = MeldeEngine.subject(data, id: lesson.subjectId)
        let attributes = LessonActivityAttributes(
            lessonID: "preview-\(lesson.lessonId)",
            subjectName: subject?.name ?? L("Unterricht"),
            colorKey: subject?.color.rawValue ?? SubjectColor.blue.rawValue,
            symbolName: subject?.symbolName ?? "book.closed",
            start: start,
            end: end
        )
        let state = LessonActivityAttributes.ContentState(
            count: MeldeEngine.count(data, lessonID: lesson.lessonId, on: day, calendar: calendar),
            weekTotal: Int(MeldeEngine.weekSummary(data, containing: now, calendar: calendar)?.total ?? 0)
        )
        do {
            let activity = try Activity<LessonActivityAttributes>.request(
                attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil
            )
            // Ended right away but kept visible for two minutes.
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(now.addingTimeInterval(120)))
            return .shown
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
