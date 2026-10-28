import Foundation
import MeldeCore

/// Pure functions over `AppData` shared by the app, widgets, the Melden control
/// and notification actions, so every surface logs a Meldung the same way.
/// The rules themselves live in the Rust core.
public nonisolated enum MeldeEngine: Sendable {
    /// Minutes after the bell in which a Meldung still counts for the lesson that just ended.
    public static let participationGraceMinutes: UInt16 = 5

    /// `allCourses` keeps hidden parallel courses (the Stundenplan grid offers them as alternatives).
    public static func timetable(_ data: AppData, calendar: Calendar, allCourses: Bool = false) -> FfiTimetable {
        FfiTimetable(
            lessons: (allCourses ? data.lessons : attendedLessons(data)).map(ffiLesson),
            holidays: data.holidays.map {
                FfiHoliday(
                    name: $0.name,
                    firstDay: FfiDate($0.firstDay, calendar: calendar),
                    lastDay: FfiDate($0.lastDay, calendar: calendar)
                )
            },
            changes: data.changes.map {
                FfiTimetableChange(
                    lessonId: $0.lessonID.uuidString,
                    date: FfiDate($0.date, calendar: calendar),
                    kind: $0.kind == .cancelled
                        ? .cancelled
                        : .substituted(subjectId: $0.substituteSubjectID?.uuidString, room: $0.room)
                )
            },
            weekAReference: data.preferences.weekAReference.map { FfiDate($0, calendar: calendar) }
        )
    }

    /// Lessons minus the parallel courses the student hid in the Stundenplan
    /// (`AppModel.chooseCourse`), so Melden, check-ins and widgets use the attended course.
    /// Hidden keys are "weekday|start|subject|teacher"; lessons carry no teacher, so
    /// the first three parts are compared. A slot never loses all of its lessons.
    public static func attendedLessons(_ data: AppData) -> [Lesson] {
        guard !data.preferences.hiddenCourses.isEmpty else { return data.lessons }
        let hidden = Set(data.preferences.hiddenCourses.map { $0.split(separator: "|", omittingEmptySubsequences: false).prefix(3).joined(separator: "|") })
        let names = Dictionary(data.subjects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        func isHidden(_ l: Lesson) -> Bool {
            hidden.contains("\(l.weekday)|\(l.startMinute)|\(names[l.subjectID] ?? "")")
        }
        return data.lessons.filter { lesson in
            guard isHidden(lesson) else { return true }
            let slot = data.lessons.filter { $0.weekday == lesson.weekday && $0.startMinute == lesson.startMinute && $0.parity == lesson.parity }
            return slot.allSatisfy(isHidden)
        }
    }

    public static func ffiLesson(_ l: Lesson) -> FfiLesson {
        let parity: FfiWeekParity = switch l.parity {
        case .every: .every
        case .a: .a
        case .b: .b
        }
        return FfiLesson(
            id: l.id.uuidString,
            subjectId: l.subjectID.uuidString,
            weekday: FfiWeekday(mondayIndex: l.weekday),
            startMinute: UInt16(clamping: l.startMinute),
            endMinute: UInt16(clamping: l.endMinute),
            parity: parity,
            room: l.room.isEmpty ? nil : l.room
        )
    }

    public static func entries(_ data: AppData, calendar: Calendar) -> [FfiParticipationEntry] {
        data.participation.map {
            FfiParticipationEntry(
                id: $0.id.uuidString,
                subjectId: $0.subjectID?.uuidString,
                at: FfiDateTime($0.recordedAt, calendar: calendar)
            )
        }
    }

    public static func currentLesson(_ data: AppData, at date: Date, calendar: Calendar) -> FfiOccurrence? {
        try? timetableCurrent(timetable: timetable(data, calendar: calendar), at: FfiDateTime(date, calendar: calendar))
    }

    public static func nextLesson(_ data: AppData, after date: Date, calendar: Calendar) -> FfiOccurrence? {
        try? timetableNext(
            timetable: timetable(data, calendar: calendar),
            at: FfiDateTime(date, calendar: calendar), horizonDays: 14
        )
    }

    /// The lesson a Meldung at `date` belongs to (current lesson or one that just ended).
    public static func participationLesson(_ data: AppData, at date: Date, calendar: Calendar) -> FfiOccurrence? {
        try? timetableParticipationLesson(
            timetable: timetable(data, calendar: calendar),
            at: FfiDateTime(date, calendar: calendar),
            graceMinutes: participationGraceMinutes
        )
    }

    /// The lesson a one-tap Meldung may be booked to without asking. Nil when nothing runs,
    /// when the lesson is cancelled (e.g. a workshop replaces it) or when different
    /// subjects run in parallel and the student hasn't picked their course: Meldo never
    /// guesses, the student chooses (or assigns it later in the app).
    public static func bookableLesson(_ data: AppData, at date: Date, calendar: Calendar) -> FfiOccurrence? {
        guard let lesson = participationLesson(data, at: date, calendar: calendar), !lesson.cancelled else { return nil }
        return parallelSubjects(data, to: lesson, calendar: calendar).isEmpty ? lesson : nil
    }

    /// Other subjects taking place at the same time as `lesson` (parallel courses).
    public static func parallelSubjects(_ data: AppData, to lesson: FfiOccurrence, calendar: Calendar) -> [String] {
        let all = (try? timetableOccurrencesOn(timetable: timetable(data, calendar: calendar), date: lesson.date)) ?? []
        let others = all.filter {
            !$0.cancelled && $0.lessonId != lesson.lessonId && $0.subjectId != lesson.subjectId
                && $0.startMinute < lesson.endMinute && lesson.startMinute < $0.endMinute
        }
        return Array(Set(others.map(\.subjectId)))
    }

    /// Records a Meldung for the lesson at `date`; `nil` when no lesson may be booked without asking.
    public static func recordForLesson(in data: inout AppData, at date: Date, calendar: Calendar) -> ParticipationEntry? {
        guard let lesson = bookableLesson(data, at: date, calendar: calendar) else { return nil }
        let entry = ParticipationEntry(
            subjectID: UUID(uuidString: lesson.subjectId),
            lessonID: UUID(uuidString: lesson.lessonId),
            recordedAt: date
        )
        data.participation.append(entry)
        return entry
    }

    public static func weekSummary(_ data: AppData, containing date: Date, calendar: Calendar) -> FfiWeekSummary? {
        try? participationWeekSummary(entries: entries(data, calendar: calendar), anyDayInWeek: FfiDate(date, calendar: calendar))
    }

    /// Meldungen already recorded for one lesson on one day.
    public static func count(_ data: AppData, lessonID: String, on date: Date, calendar: Calendar) -> Int {
        data.participation.filter {
            $0.lessonID?.uuidString == lessonID && calendar.isDate($0.recordedAt, inSameDayAs: date)
        }.count
    }

    public static func subject(_ data: AppData, id: String?) -> Subject? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return data.subjects.first { $0.id == uuid }
    }
}
