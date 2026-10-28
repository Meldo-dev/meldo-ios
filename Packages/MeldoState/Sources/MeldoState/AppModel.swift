import Foundation
import MeldeCore
import MeldoKit
import Observation

/// Single source of truth for the UI. Business rules (current lesson, streaks,
/// targets, validation) are delegated to the Rust core via `MeldeEngine`; this
/// type owns state, persistence and the mapping between Swift models and FFI records.
@Observable
public final class AppModel {
    public private(set) var data: AppData
    /// User-facing problem with loading or saving, shown as a banner.
    public var storageProblem: String?
    /// The first-run tour is on screen. Kept here, not in the view, so the
    /// language switch (which rebuilds the view tree) doesn't close it.
    public var showingOnboarding = false

    public let store: LocalStore?
    public let calendar: Calendar
    private let now: () -> Date
    /// What modules keep on the model (a connection's status, say), one object per type.
    @ObservationIgnored private var moduleStates: [ObjectIdentifier: AnyObject] = [:]
    /// Run after every saved change and after a sync merged other devices' changes.
    @ObservationIgnored private var changeHandlers: [() -> Void] = []
    @ObservationIgnored private var mergeHandlers: [(_ before: AppData) -> Void] = []

    public static var participationGraceMinutes: UInt16 { MeldeEngine.participationGraceMinutes }

    public init(store: LocalStore?, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.calendar = calendar
        self.now = now
        do {
            data = try store?.load() ?? AppData()
        } catch {
            data = AppData()
            storageProblem = L("Deine gespeicherten Daten konnten nicht gelesen werden. Eine Sicherungskopie wurde behalten.")
        }
        Localization.apply(data.preferences.language)
        // An unreadable file looks empty, but its owner is not new: no tour then.
        showingOnboarding = storageProblem == nil && Onboarding.shouldShow(
            seen: data.preferences.onboardingSeen,
            hasSubjects: !data.subjects.isEmpty,
            hasUntis: data.untis != nil
        )
    }

    public var currentDate: Date { now() }

    /// The loaded data is the student's real file (it exists and could be read).
    public var hasReadableStore: Bool { store != nil && storageProblem == nil }

    // MARK: - Modules

    /// The state object of type `State` that a module keeps on this model, made on first use.
    public func moduleState<State: AnyObject>(_ make: () -> State) -> State {
        let key = ObjectIdentifier(State.self)
        if let existing = moduleStates[key] as? State { return existing }
        let state = make()
        moduleStates[key] = state
        return state
    }

    /// `handler` runs after every saved change (for example to start a backup).
    public func onChange(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    /// `handler` runs after a sync merged other devices' changes, with the data from before.
    public func onMerge(_ handler: @escaping (_ before: AppData) -> Void) {
        mergeHandlers.append(handler)
    }

    /// Whether widgets and the Melden control can see this data (App Group available).
    public var isSharedWithWidgets: Bool { store?.isShared ?? false }

    // MARK: - Persistence

    /// Applies a change to the latest stored data and saves it, so entries
    /// written meanwhile by a widget or notification action are kept.
    /// Feature extensions change data only through this.
    public func mutate(_ change: (inout AppData) -> Void) {
        guard let store else {
            change(&data)
            return
        }
        do {
            data = try store.update(change)
            storageProblem = nil
        } catch {
            change(&data)
            storageProblem = L("Änderungen konnten nicht gespeichert werden. Prüfe den freien Speicher.")
        }
        Surfaces.reload()
        refreshSchedules()
        changeHandlers.forEach { $0() }
    }

    /// Re-plans after-lesson check-ins and the Live Activity for the latest data.
    public func refreshSchedules() {
        let snapshot = data
        let calendar = calendar
        let now = now()
        Task.detached {
            await LessonCheckIns.reschedule(snapshot, calendar: calendar, now: now)
            await LessonActivity.refresh(snapshot, at: now, calendar: calendar)
        }
    }

    /// After a sync merged other devices' changes into the store: loads them and lets
    /// this device follow what happened on its other devices.
    public func applyMerged(since before: AppData) {
        reloadFromDisk()
        // Exams deleted on another device: their PDFs go here too (unless another exam uses the file).
        let kept = Set(data.exams.map(\.fileName)), ids = Set(data.exams.map(\.id))
        for exam in before.exams where !ids.contains(exam.id) && !kept.contains(exam.fileName) {
            if let url = ExamFiles.locate(exam.fileName) { try? FileManager.default.removeItem(at: url) }
        }
        // Modules follow too (an integration forgets the secrets of a connection removed elsewhere).
        mergeHandlers.forEach { $0(before) }
        // Reminders follow tasks deleted or changed on another device.
        let earlier = Set(before.tasks.map(\.id))
        for task in before.tasks where !data.tasks.contains(task) {
            if let now = data.tasks.first(where: { $0.id == task.id }) {
                Reminders.schedule(now, subjectName: subject(now.subjectID)?.name)
            } else {
                Reminders.cancel(taskID: task.id)
            }
        }
        for task in data.tasks where !earlier.contains(task.id) && task.reminderAt != nil {
            Reminders.schedule(task, subjectName: subject(task.subjectID)?.name)
        }
        Surfaces.reload()
        refreshSchedules()
    }

    /// Picks up changes made outside the app (widgets, Lock Screen, notification actions).
    public func reloadFromDisk() {
        guard let store, let fresh = try? store.load() else { return }
        data = fresh
        Localization.apply(fresh.preferences.language)
    }

    // MARK: - Preferences

    public var preferences: Preferences { data.preferences }

    public func setLanguage(_ language: AppLanguage) {
        Localization.apply(language)
        mutate { $0.preferences.language = language }
    }

    public func setAppearance(_ appearance: AppearanceChoice) {
        mutate { $0.preferences.appearance = appearance }
    }


    public func setWeeklyGoal(_ goal: Int?) {
        let clamped = goal.map { max(1, min($0, 200)) }
        mutate { $0.preferences.weeklyGoal = clamped }
    }

    public func setAskAfterLesson(_ on: Bool) {
        mutate {
            $0.preferences.askAfterLesson = on
            $0.preferences.checkInPromptDismissed = true
        }
    }

    public func dismissCheckInPrompt() {
        mutate { $0.preferences.checkInPromptDismissed = true }
    }

    public func setLiveActivities(_ on: Bool) {
        mutate { $0.preferences.liveActivities = on }
    }

    public func setShowMascot(_ on: Bool) {
        mutate { $0.preferences.showMascot = on }
    }

    public func setBarTabs(_ tabs: [String]) {
        mutate { $0.preferences.barTabs = tabs }
    }

    public func setStartTab(_ tab: String) {
        mutate { $0.preferences.startTab = tab }
    }

    public func setHaptics(_ on: Bool) {
        mutate { $0.preferences.haptics = on }
    }

    public func setHomeLayout(_ layout: [CardSlot<DashboardCard>]) {
        mutate { $0.preferences.homeLayout = layout }
    }

    public func setStatsLayout(_ layout: [CardSlot<StatsCard>]) {
        mutate { $0.preferences.statsLayout = layout }
    }

    public func setAppIcon(_ icon: AppIconChoice) {
        mutate { $0.preferences.appIcon = icon }
    }

    public func setWeekAReference(_ date: Date?) {
        mutate { $0.preferences.weekAReference = date }
    }

    /// Marks the week containing today as an A week (or B week).
    public func setCurrentWeekIsA(_ isA: Bool) {
        let today = now()
        setWeekAReference(isA ? today : calendar.date(byAdding: .weekOfYear, value: -1, to: today))
    }

    /// ISO weeks (Monday to Sunday, German KW), whatever the region's first weekday is;
    /// the Rust core counts A/B weeks the same way.
    public var isoCalendar: Calendar {
        var iso = calendar
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        return iso
    }

    public func isWeekA(_ date: Date) -> Bool {
        let calendar = isoCalendar
        guard let reference = data.preferences.weekAReference,
              let a = calendar.dateInterval(of: .weekOfYear, for: reference)?.start,
              let b = calendar.dateInterval(of: .weekOfYear, for: date)?.start
        else { return true }
        let weeks = calendar.dateComponents([.weekOfYear], from: a, to: b).weekOfYear ?? 0
        return weeks.isMultiple(of: 2)
    }

    // MARK: - Subjects

    public var subjects: [Subject] { data.subjects }

    public func subject(_ id: UUID?) -> Subject? {
        guard let id else { return nil }
        return data.subjects.first { $0.id == id }
    }

    public func upsert(_ subject: Subject) {
        var subject = subject
        subject.name = subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.name.isEmpty else { return }
        subject.updatedAt = now()
        mutate { data in
            if let i = data.subjects.firstIndex(where: { $0.id == subject.id }) {
                data.subjects[i] = subject
            } else {
                data.subjects.append(subject)
            }
        }
    }

    /// Deletes a subject and its lessons. Past Meldungen are kept without a subject.
    public func deleteSubject(_ id: UUID) {
        mutate { data in
            let lessonIDs = Set(data.lessons.filter { $0.subjectID == id }.map(\.id))
            data.subjects.removeAll { $0.id == id }
            data.lessons.removeAll { $0.subjectID == id }
            data.changes.removeAll { lessonIDs.contains($0.lessonID) }
            for i in data.changes.indices where data.changes[i].substituteSubjectID == id {
                data.changes[i].substituteSubjectID = nil
            }
            for i in data.participation.indices {
                if data.participation[i].subjectID == id { data.participation[i].subjectID = nil }
                if let lesson = data.participation[i].lessonID, lessonIDs.contains(lesson) {
                    data.participation[i].lessonID = nil
                }
            }
        }
    }

    // MARK: - Timetable

    public var lessons: [Lesson] { data.lessons }

    public func lessons(onWeekday weekday: Int) -> [Lesson] {
        data.lessons.filter { $0.weekday == weekday }.sorted { $0.startMinute < $1.startMinute }
    }

    /// Validates with the Rust core and saves when there is no conflict.
    public func save(_ lesson: Lesson) -> [FfiTimetableIssue] {
        var updated = lesson
        updated.updatedAt = now()
        let candidate = data.lessons.filter { $0.id != lesson.id } + [updated]
        let issues = validate(lessons: candidate)
        guard issues.isEmpty else { return issues }
        mutate { data in
            data.lessons.removeAll { $0.id == updated.id }
            data.lessons.append(updated)
        }
        return []
    }

    public func deleteLesson(_ id: UUID) {
        mutate { data in
            data.lessons.removeAll { $0.id == id }
            data.changes.removeAll { $0.lessonID == id }
            for i in data.participation.indices where data.participation[i].lessonID == id {
                data.participation[i].lessonID = nil
            }
        }
    }

    public func validate(lessons: [Lesson]) -> [FfiTimetableIssue] {
        var timetable = ffiTimetable
        timetable.lessons = lessons.map(MeldeEngine.ffiLesson)
        // Only the weekly plan is validated here; per-date changes are managed separately.
        timetable.changes = []
        return (try? timetableValidate(timetable: timetable)) ?? []
    }

    public var ffiTimetable: FfiTimetable { MeldeEngine.timetable(data, calendar: calendar) }

    public func occurrences(on date: Date) -> [FfiOccurrence] {
        (try? timetableOccurrencesOn(timetable: ffiTimetable, date: FfiDate(date, calendar: calendar))) ?? []
    }

    public func currentLesson(at date: Date) -> FfiOccurrence? {
        MeldeEngine.currentLesson(data, at: date, calendar: calendar)
    }

    public func nextLesson(after date: Date) -> FfiOccurrence? {
        MeldeEngine.nextLesson(data, after: date, calendar: calendar)
    }

    public func subject(for occurrence: FfiOccurrence) -> Subject? {
        subject(UUID(uuidString: occurrence.subjectId))
    }

    // MARK: - Melde Tracker

    public enum RecordOutcome: Equatable, Sendable {
        case recorded(ParticipationEntry)
        /// No lesson right now (or it's cancelled): the UI asks for the subject (second tap).
        case needsSubject
        /// Different courses run in parallel and the student hasn't picked theirs yet:
        /// the UI asks once which one (subject ids) and remembers it.
        case needsCourse([UUID])
    }

    /// One-tap recording, auto-assigned to the current lesson when possible.
    public func recordParticipation(at date: Date? = nil) -> RecordOutcome {
        let at = date ?? now()
        guard let lesson = MeldeEngine.participationLesson(data, at: at, calendar: calendar), !lesson.cancelled else { return .needsSubject }
        let parallel = MeldeEngine.parallelSubjects(data, to: lesson, calendar: calendar)
        if !parallel.isEmpty {
            return .needsCourse(([lesson.subjectId] + parallel).compactMap(UUID.init(uuidString:)))
        }
        var entry: ParticipationEntry?
        mutate { entry = MeldeEngine.recordForLesson(in: &$0, at: at, calendar: calendar) }
        guard let entry else { return .needsSubject }
        LessonCheckIns.didRecord(entry, calendar: calendar)
        return .recorded(entry)
    }

    /// The answer to "Welcher Kurs?": records the Meldung for `subjectID` and hides the
    /// other parallel courses at this time every week, so Melden doesn't ask again.
    @discardableResult
    public func recordParticipation(choosingCourse subjectID: UUID, among options: [UUID], at date: Date? = nil) -> RecordOutcome {
        let at = date ?? now()
        guard let lesson = MeldeEngine.participationLesson(data, at: at, calendar: calendar) else {
            return .recorded(recordParticipation(subjectID: subjectID, at: at))
        }
        let weekday = calendar.mondayIndex(of: at)
        let names = Dictionary(data.subjects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        mutate { data in
            var keys = Set(data.preferences.hiddenCourses)
            for option in options where option != subjectID {
                // Same "weekday|start|subject|teacher" shape as `courseKey`; the teacher isn't known here.
                keys.insert("\(weekday)|\(lesson.startMinute)|\(names[option] ?? "")|")
            }
            keys = keys.filter { !$0.hasPrefix("\(weekday)|\(lesson.startMinute)|\(names[subjectID] ?? "")|") }
            data.preferences.hiddenCourses = keys.sorted()
        }
        return recordParticipation(at: at)
    }

    @discardableResult
    public func recordParticipation(subjectID: UUID?, at date: Date? = nil) -> ParticipationEntry {
        let entry = ParticipationEntry(subjectID: subjectID, lessonID: nil, recordedAt: date ?? now())
        mutate { $0.participation.append(entry) }
        return entry
    }

    public func deleteParticipation(_ id: UUID) {
        mutate { $0.participation.removeAll { $0.id == id } }
    }

    public func reassignParticipation(_ id: UUID, to subjectID: UUID?) {
        mutate { data in
            guard let i = data.participation.firstIndex(where: { $0.id == id }) else { return }
            data.participation[i].subjectID = subjectID
            data.participation[i].lessonID = nil
        }
    }

    /// Today's Meldungen logged without a subject (e.g. from the Control Center outside a lesson).
    public func unassignedEntries(on date: Date) -> [ParticipationEntry] {
        entries(on: date).filter { $0.subjectID == nil }
    }

    public var ffiEntries: [FfiParticipationEntry] { MeldeEngine.entries(data, calendar: calendar) }

    public func weekSummary(containing date: Date) -> FfiWeekSummary? {
        MeldeEngine.weekSummary(data, containing: date, calendar: calendar)
    }

    public func streak(asOf date: Date) -> Int {
        Int((try? participationStreak(entries: ffiEntries, timetable: ffiTimetable, today: FfiDate(date, calendar: calendar))) ?? 0)
    }

    /// Totals of the `count` weeks before the week containing `date`, oldest first.
    public func previousWeekTotals(before date: Date, count: Int) -> [UInt32] {
        (1...max(count, 1)).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: date).flatMap { weekSummary(containing: $0)?.total }
        }
    }

    public func suggestedWeeklyGoal(asOf date: Date) -> Int? {
        // Holiday weeks aren't school weeks; leading empty weeks are from before
        // the student started using the app.
        let history = (1...4).reversed().compactMap { offset -> UInt32? in
            guard let day = calendar.date(byAdding: .weekOfYear, value: -offset, to: date) else { return nil }
            let monday = calendar.date(byAdding: .day, value: -calendar.mondayIndex(of: day), to: calendar.startOfDay(for: day)) ?? day
            let schoolDays = (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
            guard schoolDays.contains(where: { holiday(on: $0) == nil }) else { return nil }
            return weekSummary(containing: day)?.total
        }.drop(while: { $0 == 0 })
        return participationSuggestWeeklyTarget(recentWeekTotals: Array(history)).map(Int.init)
    }

    public func entries(on date: Date) -> [ParticipationEntry] {
        data.participation
            .filter { calendar.isDate($0.recordedAt, inSameDayAs: date) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }
}
