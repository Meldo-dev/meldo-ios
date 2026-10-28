import Foundation
import MeldeCore
import MeldoKit

/// Hausaufgaben and to-dos. Grouping, recurrence, streaks and due-date
/// suggestions come from the Rust core (melde-tasks).
extension AppModel {
    public struct TaskSection: Identifiable, Sendable {
        public let group: FfiTaskGroup
        public let tasks: [SchoolTask]
        public var id: String { "\(group)" }
    }

    public var tasks: [SchoolTask] { data.tasks }

    public func task(_ id: UUID) -> SchoolTask? {
        data.tasks.first { $0.id == id }
    }

    public func upsert(_ task: SchoolTask) {
        var task = task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.title.isEmpty else { return }
        task.dueDate = task.dueDate.map { calendar.startOfDay(for: $0) }
        task.updatedAt = currentDate
        mutate { data in
            if let i = data.tasks.firstIndex(where: { $0.id == task.id }) {
                data.tasks[i] = task
            } else {
                data.tasks.append(task)
            }
        }
        Reminders.schedule(task, subjectName: subject(task.subjectID)?.name)
    }

    public func deleteTask(_ id: UUID) {
        mutate { data in
            if let task = data.tasks.first(where: { $0.id == id }) {
                if let untisID = task.untisID { data.dismissedImports.insert("untis:\(untisID)") }
                if let teamsID = task.teamsID { data.dismissedImports.insert("teams:\(teamsID)") }
            }
            data.tasks.removeAll { $0.id == id }
        }
        Reminders.cancel(taskID: id)
    }

    /// Checks a task off (or reopens it). Completing a recurring task
    /// creates its next instance with the due date computed in Rust.
    public func toggleDone(_ id: UUID) {
        guard let original = task(id) else { return }
        let now = currentDate
        var next: SchoolTask?
        if !original.isDone, original.recurrence != .never,
           let nextDue = try? tasksNextDue(task: ffiTask(original), completedOn: FfiDate(now, calendar: calendar)),
           let dueDate = nextDue.date(in: calendar) {
            next = SchoolTask(
                title: original.title, notes: original.notes, kind: original.kind,
                subjectID: original.subjectID, dueDate: dueDate, priority: original.priority,
                recurrence: original.recurrence,
                reminderAt: original.reminderAt.flatMap { shiftReminder($0, from: original.dueDate, to: dueDate) },
                spawnedFrom: original.id
            )
        }
        // Reopening takes back the next instance it created, unless the student already finished it.
        let undone = original.isDone ? tasks.filter { $0.spawnedFrom == id && !$0.isDone }.map(\.id) : []
        mutate { data in
            guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
            data.tasks[i].completedAt = original.isDone ? nil : now
            data.tasks[i].updatedAt = now
            data.tasks.removeAll { undone.contains($0.id) }
            if let next, !data.tasks.contains(where: { $0.spawnedFrom == id }) { data.tasks.append(next) }
        }
        undone.forEach { Reminders.cancel(taskID: $0) }
        if original.isDone {
            Reminders.schedule(original, subjectName: subject(original.subjectID)?.name)
        } else {
            Reminders.cancel(taskID: id)
        }
        if let next { Reminders.schedule(next, subjectName: subject(next.subjectID)?.name) }
    }

    /// Keeps a reminder at the same offset from the due date for the next instance.
    private func shiftReminder(_ reminder: Date, from oldDue: Date?, to newDue: Date) -> Date? {
        guard let oldDue else { return nil }
        return reminder.addingTimeInterval(newDue.timeIntervalSince(oldDue))
    }

    public func taskSections(today: Date, kind: TaskKind? = nil) -> [TaskSection] {
        let filtered = data.tasks.filter { kind == nil || $0.kind == kind }
        let byID = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id.uuidString, $0) })
        let sections = (try? tasksGrouped(tasks: filtered.map(ffiTask), today: FfiDate(today, calendar: calendar))) ?? []
        return sections.map { section in
            TaskSection(group: section.group, tasks: section.taskIds.compactMap { byID[$0] })
        }
    }

    /// Open homework due today or tomorrow, most urgent first.
    public func upcomingHomework(today: Date, limit: Int = 3) -> [SchoolTask] {
        taskSections(today: today, kind: .homework)
            .filter { [.overdue, .today, .tomorrow].contains($0.group) }
            .flatMap(\.tasks)
            .prefix(limit)
            .map { $0 }
    }

    public func homeworkStreak(asOf date: Date) -> Int {
        Int((try? tasksHomeworkStreak(tasks: data.tasks.map(ffiTask), today: FfiDate(date, calendar: calendar))) ?? 0)
    }

    /// Share of this week's homework done on time, `nil` if none was due yet.
    public func homeworkOnTimeRate(weekContaining date: Date) -> Double? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date),
              let lastDay = calendar.date(byAdding: .day, value: 6, to: week.start) else { return nil }
        let last = min(lastDay, date)
        return try? tasksOnTimeRate(
            tasks: data.tasks.map(ffiTask),
            first: FfiDate(week.start, calendar: calendar),
            last: FfiDate(last, calendar: calendar)
        )
    }

    /// The subject's next lesson day after `date`: the usual due date for homework.
    public func nextLessonDay(for subjectID: UUID, after date: Date) -> Date? {
        let result = try? tasksNextLessonDate(
            timetable: ffiTimetable, subjectId: subjectID.uuidString,
            from: FfiDate(date, calendar: calendar), horizonDays: 28
        )
        return result?.date(in: calendar)
    }

    public func tasks(dueOn date: Date) -> [SchoolTask] {
        data.tasks.filter { $0.dueDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false }
    }

    private func ffiTask(_ t: SchoolTask) -> FfiTask {
        let kind: FfiTaskKind = t.kind == .homework ? .homework : .todo
        let priority: FfiPriority = switch t.priority {
        case .low: .low
        case .normal: .normal
        case .high: .high
        }
        let recurrence: FfiRecurrence = switch t.recurrence {
        case .never: .never
        case .daily: .daily
        case .weekdays: .weekdays
        case .weekly: .weekly
        case .biweekly: .biweekly
        }
        return FfiTask(
            id: t.id.uuidString,
            title: t.title,
            kind: kind,
            due: t.dueDate.map { FfiDate($0, calendar: calendar) },
            completedOn: t.completedAt.map { FfiDate($0, calendar: calendar) },
            priority: priority,
            recurrence: recurrence
        )
    }
}
