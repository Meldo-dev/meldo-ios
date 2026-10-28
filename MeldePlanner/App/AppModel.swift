import Foundation
import MeldeCore
import Observation

/// Single source of truth for the UI. Business rules (current lesson, streaks,
/// targets, validation) are delegated to the Rust core via `MeldeEngine`; this
/// type owns state, persistence and the mapping between Swift models and FFI records.
@Observable
final class AppModel {
    private(set) var data: AppData
    /// User-facing problem with loading or saving, shown as a banner.
    var storageProblem: String?
    /// A WebUntis update is running; automatic updates don't start a second one.
    var isRefreshingUntis = false
    /// After a failed automatic update, the next one waits until then (see refreshUntisIfStale).
    @ObservationIgnored var untisRetryAfter: Date?
    @ObservationIgnored var untisFailures = 0
    /// Bumped by "WebUntis trennen" / "Teams trennen". An import that started
    /// earlier stops writing, so it can't bring back the connection or its secret.
    @ObservationIgnored var untisGeneration = 0
    @ObservationIgnored var teamsGeneration = 0
    /// The first-run tour is on screen. Kept here, not in the view, so the
    /// language switch (which rebuilds the view tree) doesn't close it.
    var showingOnboarding = false
    /// Google Drive sync and backup (per device, see `AppModel+GoogleDrive`).
    var driveState = DriveState.off
    var isSyncingWithDrive = false
    /// The connected Google account (not secret, per device) and the last backup.
    var driveAccount = UserDefaults.standard.string(forKey: AppModel.driveAccountKey)
    var lastDriveSync = UserDefaults.standard.object(forKey: AppModel.driveLastSyncKey) as? Date
    var driveProblem: String?
    var driveSyncTask: Task<Void, Never>?
    /// The Drive sync running now; "trennen" cancels it between steps.
    @ObservationIgnored var driveRunTask: Task<Void, any Error>?
    /// Bumped by "Google Drive trennen": work started earlier stops writing.
    @ObservationIgnored var driveGeneration = 0
    @ObservationIgnored var driveAccess: GoogleClient.Tokens?

    let store: LocalStore?
    let calendar: Calendar
    private let now: () -> Date

    static var participationGraceMinutes: UInt16 { MeldeEngine.participationGraceMinutes }

    init(store: LocalStore?, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
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
        if store != nil, storageProblem == nil {
            // The Drive sign-in and key are per install: after a reinstall, sign in again.
            Keychain.forgetEarlierInstall(hasConnection: data.untis != nil || data.teams != nil,
                                          alwaysForget: [Self.driveTokenAccount, Self.driveKeyAccount])
            UntisSilentLogin.keepWebLoginOutOfBackups()
            driveState = Self.storedDriveState()
        }
        // An unreadable file looks empty, but its owner is not new: no tour then.
        showingOnboarding = storageProblem == nil && Onboarding.shouldShow(
            seen: data.preferences.onboardingSeen,
            hasSubjects: !data.subjects.isEmpty,
            hasUntis: data.untis != nil
        )
    }

    var currentDate: Date { now() }

    /// Whether widgets and the Melden control can see this data (App Group available).
    var isSharedWithWidgets: Bool { store?.isShared ?? false }

    // MARK: - Persistence

    /// Applies a change to the latest stored data and saves it, so entries
    /// written meanwhile by a widget or notification action are kept.
    /// Feature extensions change data only through this.
    func mutate(_ change: (inout AppData) -> Void) {
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
        scheduleDriveSync()
    }

    /// Re-plans after-lesson check-ins and the Live Activity for the latest data.
    func refreshSchedules() {
        let snapshot = data
        let calendar = calendar
        let now = now()
        Task.detached {
            await LessonCheckIns.reschedule(snapshot, calendar: calendar, now: now)
            await LessonActivity.refresh(snapshot, at: now, calendar: calendar)
        }
    }

    /// Picks up changes made outside the app (widgets, Lock Screen, notification actions).
    func reloadFromDisk() {
        guard let store, let fresh = try? store.load() else { return }
        data = fresh
        Localization.apply(fresh.preferences.language)
    }

    // MARK: - Preferences

    var preferences: Preferences { data.preferences }

    func setLanguage(_ language: AppLanguage) {
        Localization.apply(language)
        mutate { $0.preferences.language = language }
    }

    func setAppearance(_ appearance: AppearanceChoice) {
        mutate { $0.preferences.appearance = appearance }
    }


    func setWeeklyGoal(_ goal: Int?) {
        let clamped = goal.map { max(1, min($0, 200)) }
        mutate { $0.preferences.weeklyGoal = clamped }
    }

    func setAskAfterLesson(_ on: Bool) {
        mutate {
            $0.preferences.askAfterLesson = on
            $0.preferences.checkInPromptDismissed = true
        }
    }

    func dismissCheckInPrompt() {
        mutate { $0.preferences.checkInPromptDismissed = true }
    }

    func setLiveActivities(_ on: Bool) {
        mutate { $0.preferences.liveActivities = on }
    }

    func setShowMascot(_ on: Bool) {
        mutate { $0.preferences.showMascot = on }
    }

    /// Teams is offered once switched on, or while a connection from before still exists.
    var teamsAvailable: Bool { preferences.teamsEnabled || data.teams != nil }

    func setBarTabs(_ tabs: [String]) {
        mutate { $0.preferences.barTabs = tabs }
    }

    func setStartTab(_ tab: String) {
        mutate { $0.preferences.startTab = tab }
    }

    func setTeamsEnabled(_ on: Bool) {
        mutate { $0.preferences.teamsEnabled = on }
    }

    func setHaptics(_ on: Bool) {
        mutate { $0.preferences.haptics = on }
    }

    func setHomeLayout(_ layout: [CardSlot<DashboardCard>]) {
        mutate { $0.preferences.homeLayout = layout }
    }

    func setStatsLayout(_ layout: [CardSlot<StatsCard>]) {
        mutate { $0.preferences.statsLayout = layout }
    }

    func setAppIcon(_ icon: AppIconChoice) {
        mutate { $0.preferences.appIcon = icon }
    }

    func setWeekAReference(_ date: Date?) {
        mutate { $0.preferences.weekAReference = date }
    }

    /// Marks the week containing today as an A week (or B week).
    func setCurrentWeekIsA(_ isA: Bool) {
        let today = now()
        setWeekAReference(isA ? today : calendar.date(byAdding: .weekOfYear, value: -1, to: today))
    }

    /// ISO weeks (Monday to Sunday, German KW), whatever the region's first weekday is;
    /// the Rust core counts A/B weeks the same way.
    var isoCalendar: Calendar {
        var iso = calendar
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        return iso
    }

    func isWeekA(_ date: Date) -> Bool {
        let calendar = isoCalendar
        guard let reference = data.preferences.weekAReference,
              let a = calendar.dateInterval(of: .weekOfYear, for: reference)?.start,
              let b = calendar.dateInterval(of: .weekOfYear, for: date)?.start
        else { return true }
        let weeks = calendar.dateComponents([.weekOfYear], from: a, to: b).weekOfYear ?? 0
        return weeks.isMultiple(of: 2)
    }

    // MARK: - Subjects

    var subjects: [Subject] { data.subjects }

    func subject(_ id: UUID?) -> Subject? {
        guard let id else { return nil }
        return data.subjects.first { $0.id == id }
    }

    func upsert(_ subject: Subject) {
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
    func deleteSubject(_ id: UUID) {
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

    var lessons: [Lesson] { data.lessons }

    func lessons(onWeekday weekday: Int) -> [Lesson] {
        data.lessons.filter { $0.weekday == weekday }.sorted { $0.startMinute < $1.startMinute }
    }

    /// Validates with the Rust core and saves when there is no conflict.
    func save(_ lesson: Lesson) -> [FfiTimetableIssue] {
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

    func deleteLesson(_ id: UUID) {
        mutate { data in
            data.lessons.removeAll { $0.id == id }
            data.changes.removeAll { $0.lessonID == id }
            for i in data.participation.indices where data.participation[i].lessonID == id {
                data.participation[i].lessonID = nil
            }
        }
    }

    func validate(lessons: [Lesson]) -> [FfiTimetableIssue] {
        var timetable = ffiTimetable
        timetable.lessons = lessons.map(MeldeEngine.ffiLesson)
        // Only the weekly plan is validated here; per-date changes are managed separately.
        timetable.changes = []
        return (try? timetableValidate(timetable: timetable)) ?? []
    }

    var ffiTimetable: FfiTimetable { MeldeEngine.timetable(data, calendar: calendar) }

    func occurrences(on date: Date) -> [FfiOccurrence] {
        (try? timetableOccurrencesOn(timetable: ffiTimetable, date: FfiDate(date, calendar: calendar))) ?? []
    }

    func currentLesson(at date: Date) -> FfiOccurrence? {
        MeldeEngine.currentLesson(data, at: date, calendar: calendar)
    }

    func nextLesson(after date: Date) -> FfiOccurrence? {
        MeldeEngine.nextLesson(data, after: date, calendar: calendar)
    }

    func subject(for occurrence: FfiOccurrence) -> Subject? {
        subject(UUID(uuidString: occurrence.subjectId))
    }

    // MARK: - Melde Tracker

    enum RecordOutcome: Equatable {
        case recorded(ParticipationEntry)
        /// No lesson right now (or it's cancelled): the UI asks for the subject (second tap).
        case needsSubject
        /// Different courses run in parallel and the student hasn't picked theirs yet:
        /// the UI asks once which one (subject ids) and remembers it.
        case needsCourse([UUID])
    }

    /// One-tap recording, auto-assigned to the current lesson when possible.
    func recordParticipation(at date: Date? = nil) -> RecordOutcome {
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
    func recordParticipation(choosingCourse subjectID: UUID, among options: [UUID], at date: Date? = nil) -> RecordOutcome {
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
    func recordParticipation(subjectID: UUID?, at date: Date? = nil) -> ParticipationEntry {
        let entry = ParticipationEntry(subjectID: subjectID, lessonID: nil, recordedAt: date ?? now())
        mutate { $0.participation.append(entry) }
        return entry
    }

    func deleteParticipation(_ id: UUID) {
        mutate { $0.participation.removeAll { $0.id == id } }
    }

    func reassignParticipation(_ id: UUID, to subjectID: UUID?) {
        mutate { data in
            guard let i = data.participation.firstIndex(where: { $0.id == id }) else { return }
            data.participation[i].subjectID = subjectID
            data.participation[i].lessonID = nil
        }
    }

    /// Today's Meldungen logged without a subject (e.g. from the Control Center outside a lesson).
    func unassignedEntries(on date: Date) -> [ParticipationEntry] {
        entries(on: date).filter { $0.subjectID == nil }
    }

    private var ffiEntries: [FfiParticipationEntry] { MeldeEngine.entries(data, calendar: calendar) }

    func weekSummary(containing date: Date) -> FfiWeekSummary? {
        MeldeEngine.weekSummary(data, containing: date, calendar: calendar)
    }

    func streak(asOf date: Date) -> Int {
        Int((try? participationStreak(entries: ffiEntries, timetable: ffiTimetable, today: FfiDate(date, calendar: calendar))) ?? 0)
    }

    /// Totals of the `count` weeks before the week containing `date`, oldest first.
    func previousWeekTotals(before date: Date, count: Int) -> [UInt32] {
        (1...max(count, 1)).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: date).flatMap { weekSummary(containing: $0)?.total }
        }
    }

    func suggestedWeeklyGoal(asOf date: Date) -> Int? {
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

    func entries(on date: Date) -> [ParticipationEntry] {
        data.participation
            .filter { calendar.isDate($0.recordedAt, inSameDayAs: date) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }
}
