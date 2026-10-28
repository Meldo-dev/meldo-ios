import Foundation
import MeldeCore
import UserNotifications

/// "Hast du dich gemeldet?" after each lesson, answerable from the notification
/// without opening the app. Local notifications only (no paid account needed).
/// Cancelled lessons, holidays and lessons with a logged Meldung are skipped.
nonisolated enum LessonCheckIns {
    static let category = "LESSON_CHECKIN"
    private static let prefix = "checkin-"
    private enum Action: String {
        case once = "CHECKIN_ONCE"
        case twice = "CHECKIN_TWICE"
        case skip = "CHECKIN_SKIP"
    }

    /// iOS keeps at most 64 pending notifications per app; leave room for task reminders.
    private static let limit = 40
    private static let daysAhead = 7

    static func registerCategory() {
        let actions = [
            UNNotificationAction(identifier: Action.once.rawValue, title: L("Ja, einmal")),
            UNNotificationAction(identifier: Action.twice.rawValue, title: L("Ja, zweimal")),
            UNNotificationAction(identifier: Action.skip.rawValue, title: L("Diesmal nicht")),
        ]
        let category = UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private static func id(lessonID: String, day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(prefix)\(lessonID)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Replaces all pending check-ins with the next week's lessons.
    static func reschedule(_ data: AppData, calendar: Calendar, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard data.preferences.askAfterLesson else { return }

        let timetable = MeldeEngine.timetable(data, calendar: calendar)
        var scheduled = 0
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let occurrences = (try? timetableOccurrencesOn(timetable: timetable, date: FfiDate(day, calendar: calendar))) ?? []
            for occurrence in occurrences where !occurrence.cancelled {
                guard scheduled < limit else { return }
                guard let end = calendar.date(minuteOfDay: Int(occurrence.endMinute) + 1, on: day), end > now else { continue }
                if MeldeEngine.count(data, lessonID: occurrence.lessonId, on: day, calendar: calendar) > 0 { continue }
                let subject = MeldeEngine.subject(data, id: occurrence.subjectId)
                let content = UNMutableNotificationContent()
                let subjectName = subject?.name ?? L("Die Stunde")
                content.title = L("\(subjectName) ist vorbei")
                content.body = L("Hast du dich gemeldet?")
                content.sound = .default
                content.categoryIdentifier = category
                content.threadIdentifier = "checkins"
                content.userInfo = [
                    "lessonID": occurrence.lessonId,
                    "subjectID": occurrence.subjectId,
                    // Logged one minute before the bell so it belongs to that lesson.
                    "recordedAt": end.addingTimeInterval(-120).timeIntervalSince1970,
                ]
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: end),
                    repeats: false
                )
                try? await center.add(UNNotificationRequest(
                    identifier: id(lessonID: occurrence.lessonId, day: day, calendar: calendar),
                    content: content, trigger: trigger
                ))
                scheduled += 1
            }
        }
    }

    /// A Meldung was logged during the lesson: no need to ask afterwards.
    static func didRecord(_ entry: ParticipationEntry, calendar: Calendar) {
        guard let lessonID = entry.lessonID?.uuidString else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [id(lessonID: lessonID, day: entry.recordedAt, calendar: calendar)]
        )
    }

    /// The answer from a check-in notification, copied out of `userInfo` so it
    /// can cross threads safely.
    nonisolated struct Answer: Sendable {
        var actionIdentifier: String
        var lessonID: String
        var subjectID: String
        var recordedAt: TimeInterval
    }

    /// `nil` for a plain tap or "Diesmal nicht": nothing to save.
    static func answer(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> Answer? {
        guard actionIdentifier == Action.once.rawValue || actionIdentifier == Action.twice.rawValue,
              let lessonID = userInfo["lessonID"] as? String,
              let subjectID = userInfo["subjectID"] as? String,
              let seconds = userInfo["recordedAt"] as? TimeInterval else { return nil }
        return Answer(actionIdentifier: actionIdentifier, lessonID: lessonID, subjectID: subjectID, recordedAt: seconds)
    }

    static func handle(_ answer: Answer, store: LocalStore?) -> Bool {
        handle(
            actionIdentifier: answer.actionIdentifier,
            userInfo: ["lessonID": answer.lessonID, "subjectID": answer.subjectID, "recordedAt": answer.recordedAt],
            store: store
        )
    }

    /// Handles a tap on "Ja, einmal" / "Ja, zweimal". Returns whether data changed.
    @discardableResult
    static func handle(actionIdentifier: String, userInfo: [AnyHashable: Any], store: LocalStore?) -> Bool {
        let count: Int
        switch Action(rawValue: actionIdentifier) {
        case .once: count = 1
        case .twice: count = 2
        default: return false
        }
        guard let store,
              let lessonID = userInfo["lessonID"] as? String,
              let subjectID = userInfo["subjectID"] as? String,
              let seconds = userInfo["recordedAt"] as? TimeInterval else { return false }
        let recordedAt = Date(timeIntervalSince1970: seconds)
        let lesson = UUID(uuidString: lessonID)
        var added = false
        // The notification can be answered long after it was posted: count a lesson once,
        // and don't bring back a subject deleted meanwhile.
        guard (try? store.update { data in
            guard !data.participation.contains(where: {
                $0.lessonID == lesson && Calendar.current.isDate($0.recordedAt, inSameDayAs: recordedAt)
            }) else { return }
            let subject = UUID(uuidString: subjectID).flatMap { id in data.subjects.contains { $0.id == id } ? id : nil }
            data.participation.append(contentsOf: (0..<count).map { i in
                ParticipationEntry(subjectID: subject, lessonID: lesson, recordedAt: recordedAt.addingTimeInterval(TimeInterval(i)))
            })
            added = true
        }) != nil, added else { return false }
        Surfaces.reload()
        return true
    }
}
