import Foundation

/// A school subject (Fach). Colors are palette keys, never raw values, so
/// every theme and appearance can render them accessibly.
nonisolated struct Subject: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var shortName: String = ""
    var color: SubjectColor = .blue
    var symbolName: String = "book.closed"
    var teacher: String = ""
    var updatedAt = Date()
    /// Untis short name when imported from WebUntis; matches subjects across imports.
    var untisKey: String?

    var displayShortName: String {
        shortName.isEmpty ? String(name.prefix(3)) : shortName
    }
}

nonisolated enum WeekParity: String, Codable, CaseIterable, Identifiable {
    case every, a, b
    var id: String { rawValue }
}

/// A recurring timetable slot. `weekday` is Monday-first (0 = Montag).
nonisolated struct Lesson: Identifiable, Codable, Hashable {
    var id = UUID()
    var subjectID: UUID
    var weekday: Int
    var startMinute: Int
    var endMinute: Int
    var parity: WeekParity = .every
    var room: String = ""
    var updatedAt = Date()
    /// `true` when this lesson came from WebUntis and is updated by later imports.
    var fromUntis: Bool?
}

/// A change to one lesson on one date (Ausfall or Vertretung), e.g. from WebUntis.
nonisolated struct TimetableChangeRecord: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case cancelled, substituted }

    var id = UUID()
    var lessonID: UUID
    /// The day (local midnight).
    var date: Date
    var kind: Kind
    var substituteSubjectID: UUID?
    var room: String?
    var fromUntis: Bool?
}

/// The student's WebUntis connection. The password is kept in the Keychain, never here.
nonisolated struct UntisLink: Codable, Hashable {
    var server: String
    var loginName: String
    var schoolName: String
    var user: String
    var lastSync: Date?
    /// Logged in through the school's own login page (e.g. Microsoft 365). The
    /// Keychain then holds the WebUntis session cookies instead of a password.
    var browserLogin: Bool?
    /// The WebUntis link the student tapped to reach the school's login (e.g.
    /// "/WebUntis/oauth2/authorization/office365"). A path on `server`, not a secret;
    /// the background renewal opens it instead of the start page.
    var ssoPath: String?
}

nonisolated struct Holiday: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var firstDay: Date
    var lastDay: Date
    /// Imported from WebUntis; replaced on every import.
    var fromUntis: Bool?
}

/// One recorded Meldung. An activity count, never a grade.
nonisolated struct ParticipationEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var subjectID: UUID?
    var lessonID: UUID?
    var recordedAt: Date
}

nonisolated enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case german = "de"
    case english = "en"

    var id: String { rawValue }

    /// Shown in its own language so users can always find theirs.
    var nativeName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }
}

nonisolated enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case homework, todo
    var id: String { rawValue }
}

nonisolated enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case low, normal, high
    var id: String { rawValue }
}

nonisolated enum TaskRecurrence: String, Codable, CaseIterable, Identifiable {
    case never, daily, weekdays, weekly, biweekly
    var id: String { rawValue }
}

/// A Hausaufgabe or to-do. Named `SchoolTask` to stay clear of Swift's `Task`.
nonisolated struct SchoolTask: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var kind: TaskKind = .homework
    var subjectID: UUID?
    /// Due day (local midnight); `nil` for undated to-dos.
    var dueDate: Date?
    var completedAt: Date?
    var priority: TaskPriority = .normal
    var recurrence: TaskRecurrence = .never
    var reminderAt: Date?
    var updatedAt = Date()
    /// Homework imported from WebUntis; keeps it from being added twice.
    var untisID: Int64?
    /// Assignment imported from Microsoft Teams (Graph id).
    var teamsID: String?
    /// The recurring task whose completion created this one; reopening that task removes it again.
    var spawnedFrom: UUID?

    var isDone: Bool { completedAt != nil }
}

/// A scanned or imported exam (Klassenarbeit, Klausur, Test) stored as a PDF.
nonisolated struct ExamDocument: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var subjectID: UUID?
    var date: Date
    /// Path inside Documents/Scans, e.g. "Mathematik/Exams/1. Klausur (12.10.2026).pdf".
    var fileName: String
    var pageCount: Int
    /// The grade as written by the teacher (e.g. "2-" or "11 P."), shown as-is.
    var grade: String = ""
    var notes: String = ""
    var updatedAt = Date()
    /// `nil` in files from version 0.2, which only had exams.
    var category: DocumentCategory?

    var kind: DocumentCategory { category ?? .exam }
}

/// What a scan is; also its folder in the Files app (English names, as shown there).
nonisolated enum DocumentCategory: String, Codable, CaseIterable, Identifiable {
    case exam, worksheet, document
    var id: String { rawValue }

    var folderName: String {
        switch self {
        case .exam: "Exams"
        case .worksheet: "Worksheets"
        case .document: "Documents"
        }
    }
}

/// Cards on the home screen; order and visibility are customizable.
nonisolated enum DashboardCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, weekPreview, participation, streak, homework, exams, news, absences
    case nextLesson, weekChart, nextHoliday, todos, grades
    var id: String { rawValue }
}

/// Cards on the Statistik tab.
nonisolated enum StatsCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case perDay, bySubject, trend
    var id: String { rawValue }
}

/// How much room a card takes, like tiles on a console home screen.
nonisolated enum CardSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: String { rawValue }
}

/// A visible card and its size, in display order.
nonisolated struct CardSlot<Kind: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var kind: Kind
    var size: CardSize
}

nonisolated extension CardSlot where Kind == DashboardCard {
    static var defaultHome: [CardSlot<DashboardCard>] { [
        .init(kind: .today, size: .large),
        .init(kind: .participation, size: .small),
        .init(kind: .streak, size: .small),
        .init(kind: .weekPreview, size: .medium),
        .init(kind: .homework, size: .medium),
        .init(kind: .exams, size: .medium),
        .init(kind: .news, size: .medium),
        .init(kind: .absences, size: .small),
    ] }
}

nonisolated extension CardSlot where Kind == StatsCard {
    static var defaultStats: [CardSlot<StatsCard>] { [
        .init(kind: .perDay, size: .medium),
        .init(kind: .bySubject, size: .medium),
        .init(kind: .trend, size: .large),
    ] }
}

/// Alternate app icons (work with free signing).
nonisolated enum AppIconChoice: String, Codable, CaseIterable, Identifiable {
    case standard, orange, night
    var id: String { rawValue }
    /// Asset catalog name for `setAlternateIconName`; `nil` is the default icon.
    var assetName: String? {
        switch self {
        case .standard: nil
        case .orange: "AppIcon-Orange"
        case .night: "AppIcon-Night"
        }
    }
}

nonisolated struct Preferences: Codable, Hashable {
    var language: AppLanguage = .german
    var theme: AppTheme = .orange
    var appearance: AppearanceChoice = .system
    /// Weekly Melde target; `nil` until the student sets or accepts one.
    var weeklyGoal: Int?
    /// Any date in an A week; enables A/B-week lessons.
    var weekAReference: Date?
    /// Ask "Hast du dich gemeldet?" after each lesson (local notification).
    var askAfterLesson = false
    /// Show a Live Activity during lessons.
    var liveActivities = true
    var showMascot = true
    var haptics = true
    /// Start screen cards with their sizes, in display order; missing cards are hidden.
    var homeLayout: [CardSlot<DashboardCard>] = CardSlot<DashboardCard>.defaultHome
    /// Statistik cards with their sizes.
    var statsLayout: [CardSlot<StatsCard>] = CardSlot<StatsCard>.defaultStats
    /// Parallel courses the student doesn't attend, as "weekday|start|subject".
    var hiddenCourses: [String] = []
    var gradeScale: GradeScaleChoice = .traditional
    /// Share of written grades in a subject average (the rest is oral).
    var writtenWeight: Double = 0.5
    /// What + and − add or subtract on the 1–6 scale (e.g. 0.33 or 0.25).
    var tendencyStep: Double = 0.33
    /// For the excuse note (Entschuldigung).
    var studentName: String = ""
    var className: String = ""
    var excuseSalutation: String = ""
    var adultStudent: Bool = false
    var appIcon: AppIconChoice = .standard
    /// The start screen stops suggesting after-lesson check-ins once answered.
    var checkInPromptDismissed = false
    /// The first-run tour was finished or skipped. Students who already have
    /// data never see it, so older files don't need this set.
    var onboardingSeen = false
    /// Microsoft Teams stays hidden until the student turns it on: many schools must
    /// allow the app first (Microsoft admin consent).
    var teamsEnabled = false
    /// The two places in the tab bar after Start and Stundenplan (AppTab raw values).
    var barTabs: [String] = ["tasks", "grades"]
    /// The tab Meldo opens on (AppTab raw value).
    var startTab = "home"

    init() {}

    enum CodingKeys: String, CodingKey {
        case language, theme, appearance, weeklyGoal, weekAReference, askAfterLesson, liveActivities
        case showMascot, haptics, homeLayout, statsLayout, appIcon, checkInPromptDismissed, hiddenCourses, onboardingSeen, teamsEnabled, barTabs, startTab
        case gradeScale, writtenWeight, tendencyStep, studentName, className, excuseSalutation, adultStudent
        /// Read only, to migrate layouts from version 0.2.
        case dashboardCards
    }

    // Every field is optional when decoding, so files from older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Turkish was dropped: "tr" and any unknown language fall back to German.
        language = (try? c.decodeIfPresent(String.self, forKey: .language)).flatMap { $0.flatMap(AppLanguage.init(rawValue:)) } ?? .german
        // Older versions mixed appearance into the theme ("light", "dark", "purple", …).
        let rawTheme = try c.decodeIfPresent(String.self, forKey: .theme) ?? AppTheme.orange.rawValue
        // Color themes were dropped: Meldo is always orange (only light/dark/system remain).
        theme = .orange
        appearance = try c.decodeIfPresent(AppearanceChoice.self, forKey: .appearance)
            ?? AppearanceChoice(rawValue: rawTheme) ?? .system
        weeklyGoal = try c.decodeIfPresent(Int.self, forKey: .weeklyGoal)
        weekAReference = try c.decodeIfPresent(Date.self, forKey: .weekAReference)
        askAfterLesson = try c.decodeIfPresent(Bool.self, forKey: .askAfterLesson) ?? false
        liveActivities = try c.decodeIfPresent(Bool.self, forKey: .liveActivities) ?? true
        showMascot = try c.decodeIfPresent(Bool.self, forKey: .showMascot) ?? true
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        if let layout = try c.decodeIfPresent([CardSlot<DashboardCard>].self, forKey: .homeLayout) {
            homeLayout = layout
        } else if let old = try? c.decodeIfPresent([String].self, forKey: .dashboardCards) {
            // Version 0.2 stored only the order; keep the student's choice, add the new cards.
            let kept: [DashboardCard] = old.compactMap(DashboardCard.init(rawValue:))
            let legacy: [DashboardCard] = [.today, .participation, .homework]
            let defaults: [CardSlot<DashboardCard>] = CardSlot<DashboardCard>.defaultHome
            let keptSlots: [CardSlot<DashboardCard>] = kept.compactMap { kind in defaults.first { $0.kind == kind } }
            let added: [CardSlot<DashboardCard>] = defaults.filter { !kept.contains($0.kind) && !legacy.contains($0.kind) }
            homeLayout = keptSlots + added
        }
        statsLayout = try c.decodeIfPresent([CardSlot<StatsCard>].self, forKey: .statsLayout) ?? CardSlot<StatsCard>.defaultStats
        hiddenCourses = try c.decodeIfPresent([String].self, forKey: .hiddenCourses) ?? []
        gradeScale = try c.decodeIfPresent(GradeScaleChoice.self, forKey: .gradeScale) ?? .traditional
        writtenWeight = try c.decodeIfPresent(Double.self, forKey: .writtenWeight) ?? 0.5
        tendencyStep = try c.decodeIfPresent(Double.self, forKey: .tendencyStep) ?? 0.33
        studentName = try c.decodeIfPresent(String.self, forKey: .studentName) ?? ""
        className = try c.decodeIfPresent(String.self, forKey: .className) ?? ""
        excuseSalutation = try c.decodeIfPresent(String.self, forKey: .excuseSalutation) ?? ""
        adultStudent = try c.decodeIfPresent(Bool.self, forKey: .adultStudent) ?? false
        appIcon = try c.decodeIfPresent(AppIconChoice.self, forKey: .appIcon) ?? .standard
        checkInPromptDismissed = try c.decodeIfPresent(Bool.self, forKey: .checkInPromptDismissed) ?? false
        onboardingSeen = try c.decodeIfPresent(Bool.self, forKey: .onboardingSeen) ?? false
        teamsEnabled = try c.decodeIfPresent(Bool.self, forKey: .teamsEnabled) ?? false
        barTabs = try c.decodeIfPresent([String].self, forKey: .barTabs) ?? ["tasks", "grades"]
        startTab = try c.decodeIfPresent(String.self, forKey: .startTab) ?? "home"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(language, forKey: .language)
        try c.encode(theme, forKey: .theme)
        try c.encode(appearance, forKey: .appearance)
        try c.encodeIfPresent(weeklyGoal, forKey: .weeklyGoal)
        try c.encodeIfPresent(weekAReference, forKey: .weekAReference)
        try c.encode(askAfterLesson, forKey: .askAfterLesson)
        try c.encode(liveActivities, forKey: .liveActivities)
        try c.encode(showMascot, forKey: .showMascot)
        try c.encode(haptics, forKey: .haptics)
        try c.encode(homeLayout, forKey: .homeLayout)
        try c.encode(statsLayout, forKey: .statsLayout)
        try c.encode(hiddenCourses, forKey: .hiddenCourses)
        try c.encode(gradeScale, forKey: .gradeScale)
        try c.encode(writtenWeight, forKey: .writtenWeight)
        try c.encode(tendencyStep, forKey: .tendencyStep)
        try c.encode(studentName, forKey: .studentName)
        try c.encode(className, forKey: .className)
        try c.encode(excuseSalutation, forKey: .excuseSalutation)
        try c.encode(adultStudent, forKey: .adultStudent)
        try c.encode(appIcon, forKey: .appIcon)
        try c.encode(checkInPromptDismissed, forKey: .checkInPromptDismissed)
        try c.encode(onboardingSeen, forKey: .onboardingSeen)
        try c.encode(teamsEnabled, forKey: .teamsEnabled)
        try c.encode(barTabs, forKey: .barTabs)
        try c.encode(startTab, forKey: .startTab)
    }
}

/// One dated period exactly as WebUntis shows it (Untis-style timetable).
nonisolated struct UntisPeriodRecord: Codable, Hashable, Identifiable {
    var id: Int64
    var date: Date
    var startMinute: Int
    var endMinute: Int
    var subjectShort: String
    var subjectLong: String
    var teacher: String
    var room: String?
    /// Planned room when the period moved (Raumänderung).
    var originalRoom: String?
    var cancelled: Bool
    /// Vertretung or extra period.
    var irregular: Bool
    var exam: Bool
    var info: String?

    /// Matches `Subject.untisKey`.
    var subjectKey: String { subjectShort.isEmpty ? subjectLong : subjectShort }
}

/// One period of the school's bell schedule; breaks are the gaps between them.
nonisolated struct BellPeriod: Codable, Hashable {
    var name: String
    var startMinute: Int
    var endMinute: Int
}

/// The weeks WebUntis lets the student see, refreshed on every import.
nonisolated struct UntisTimetable: Codable, Hashable {
    var periods: [UntisPeriodRecord]
    var firstDay: Date
    /// Last day WebUntis returned; schools can limit how far ahead students see.
    var lastDay: Date
    var bells: [BellPeriod]
}

/// An absence from the WebUntis class register.
nonisolated struct UntisAbsenceRecord: Codable, Hashable, Identifiable {
    var id: Int64
    var firstDay: Date
    var lastDay: Date
    var startMinute: Int
    var endMinute: Int
    var reason: String
    var text: String
    var excused: Bool
}

/// An exam WebUntis lists for the student (Klausur, Test).
nonisolated struct UntisExamRecord: Codable, Hashable, Identifiable {
    var id: Int64
    var date: Date
    var startMinute: Int
    var endMinute: Int
    var subject: String
    var name: String
    var examType: String
    var teachers: [String]
    var rooms: [String]
    var text: String
}

/// A message of the day from the school.
nonisolated struct UntisNewsRecord: Codable, Hashable, Identifiable {
    var id: Int64
    var subject: String
    var text: String
}

/// Data from the WebUntis web API, refreshed on every import. Each list stays
/// empty when the school hides it.
nonisolated struct UntisExtras: Codable, Hashable {
    var absences: [UntisAbsenceRecord] = []
    var exams: [UntisExamRecord] = []
    var news: [UntisNewsRecord] = []
    var updated: Date
}

/// One grade the student enters (Klausur, Test, mündliche Note). Grades are
/// the student's own record for estimating averages, never official.
nonisolated struct GradeEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var subjectID: UUID
    /// 1.0–6.0 (traditional, tendency already applied) or 0–15 points.
    var value: Double
    var written: Bool
    var weight: Double = 1
    var title: String = ""
    var date: Date
}

/// How grades are entered and averaged. Configuration, not constants: schools differ.
nonisolated enum GradeScaleChoice: String, Codable, CaseIterable, Identifiable {
    /// 1 (best) to 6.
    case traditional
    /// 15 (best) to 0, Oberstufe.
    case points
    var id: String { rawValue }
}

/// The Microsoft Teams connection. The refresh token lives in the Keychain.
nonisolated struct TeamsLink: Codable, Hashable {
    var account: String
    var lastSync: Date?
}

/// Everything persisted on device. Versioned so later migrations can import it.
nonisolated struct AppData: Codable {
    /// 2: adds tasks and exams.
    static let currentSchemaVersion = 2

    var schemaVersion = AppData.currentSchemaVersion
    var subjects: [Subject] = []
    var lessons: [Lesson] = []
    var holidays: [Holiday] = []
    var participation: [ParticipationEntry] = []
    var tasks: [SchoolTask] = []
    var exams: [ExamDocument] = []
    var changes: [TimetableChangeRecord] = []
    var untis: UntisLink?
    var untisTimetable: UntisTimetable?
    var untisExtras: UntisExtras?
    var teams: TeamsLink?
    var grades: [GradeEntry] = []
    var preferences = Preferences()
    /// Imported WebUntis homework ("untis:<id>") and Teams assignments ("teams:<id>")
    /// the student deleted, so the next sync doesn't bring them back.
    var dismissedImports: Set<String> = []
    /// What changed when, for sync (see `SyncMerge`).
    var sync = SyncLedger()

    init() {}

    // Missing collections decode as empty, so version-1 files load unchanged.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        subjects = try c.decodeIfPresent([Subject].self, forKey: .subjects) ?? []
        lessons = try c.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
        holidays = try c.decodeIfPresent([Holiday].self, forKey: .holidays) ?? []
        participation = try c.decodeIfPresent([ParticipationEntry].self, forKey: .participation) ?? []
        tasks = try c.decodeIfPresent([SchoolTask].self, forKey: .tasks) ?? []
        exams = try c.decodeIfPresent([ExamDocument].self, forKey: .exams) ?? []
        changes = try c.decodeIfPresent([TimetableChangeRecord].self, forKey: .changes) ?? []
        untis = try c.decodeIfPresent(UntisLink.self, forKey: .untis)
        untisTimetable = try c.decodeIfPresent(UntisTimetable.self, forKey: .untisTimetable)
        untisExtras = try c.decodeIfPresent(UntisExtras.self, forKey: .untisExtras)
        teams = try c.decodeIfPresent(TeamsLink.self, forKey: .teams)
        grades = try c.decodeIfPresent([GradeEntry].self, forKey: .grades) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        dismissedImports = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedImports) ?? []
        sync = try c.decodeIfPresent(SyncLedger.self, forKey: .sync) ?? SyncLedger()
    }
}
