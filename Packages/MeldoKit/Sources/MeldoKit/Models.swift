import Foundation

/// A school subject (Fach). Colors are palette keys, never raw values, so
/// every theme and appearance can render them accessibly.
public nonisolated struct Subject: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var shortName: String = ""
    public var color: SubjectColor = .blue
    public var symbolName: String = "book.closed"
    public var teacher: String = ""
    public var updatedAt = Date()
    /// Untis short name when imported from WebUntis; matches subjects across imports.
    public var untisKey: String?

    public init(id: UUID = UUID(), name: String, shortName: String = "", color: SubjectColor = .blue, symbolName: String = "book.closed", teacher: String = "", updatedAt: Date = Date(), untisKey: String? = nil) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.color = color
        self.symbolName = symbolName
        self.teacher = teacher
        self.updatedAt = updatedAt
        self.untisKey = untisKey
    }

    public var displayShortName: String {
        shortName.isEmpty ? String(name.prefix(3)) : shortName
    }
}

public nonisolated enum WeekParity: String, Codable, CaseIterable, Identifiable, Sendable {
    case every, a, b
    public var id: String { rawValue }
}

/// A recurring timetable slot. `weekday` is Monday-first (0 = Montag).
public nonisolated struct Lesson: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var subjectID: UUID
    public var weekday: Int
    public var startMinute: Int
    public var endMinute: Int
    public var parity: WeekParity = .every
    public var room: String = ""
    public var updatedAt = Date()
    /// `true` when this lesson came from WebUntis and is updated by later imports.
    public var fromUntis: Bool?

    public init(id: UUID = UUID(), subjectID: UUID, weekday: Int, startMinute: Int, endMinute: Int, parity: WeekParity = .every, room: String = "", updatedAt: Date = Date(), fromUntis: Bool? = nil) {
        self.id = id
        self.subjectID = subjectID
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.parity = parity
        self.room = room
        self.updatedAt = updatedAt
        self.fromUntis = fromUntis
    }
}

/// A change to one lesson on one date (Ausfall or Vertretung), e.g. from WebUntis.
public nonisolated struct TimetableChangeRecord: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case cancelled, substituted }

    public var id = UUID()
    public var lessonID: UUID
    /// The day (local midnight).
    public var date: Date
    public var kind: Kind
    public var substituteSubjectID: UUID?
    public var room: String?
    public var fromUntis: Bool?

    public init(id: UUID = UUID(), lessonID: UUID, date: Date, kind: Kind, substituteSubjectID: UUID? = nil, room: String? = nil, fromUntis: Bool? = nil) {
        self.id = id
        self.lessonID = lessonID
        self.date = date
        self.kind = kind
        self.substituteSubjectID = substituteSubjectID
        self.room = room
        self.fromUntis = fromUntis
    }
}

/// The student's WebUntis connection. The password is kept in the Keychain, never here.
public nonisolated struct UntisLink: Codable, Hashable, Sendable {
    public var server: String
    public var loginName: String
    public var schoolName: String
    public var user: String
    public var lastSync: Date?
    /// Logged in through the school's own login page (e.g. Microsoft 365). The
    /// Keychain then holds the WebUntis session cookies instead of a password.
    public var browserLogin: Bool?
    /// The WebUntis link the student tapped to reach the school's login (e.g.
    /// "/WebUntis/oauth2/authorization/office365"). A path on `server`, not a secret;
    /// the background renewal opens it instead of the start page.
    public var ssoPath: String?

    public init(server: String, loginName: String, schoolName: String, user: String, lastSync: Date? = nil, browserLogin: Bool? = nil, ssoPath: String? = nil) {
        self.server = server
        self.loginName = loginName
        self.schoolName = schoolName
        self.user = user
        self.lastSync = lastSync
        self.browserLogin = browserLogin
        self.ssoPath = ssoPath
    }
}

public nonisolated struct Holiday: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var firstDay: Date
    public var lastDay: Date
    /// Imported from WebUntis; replaced on every import.
    public var fromUntis: Bool?

    public init(id: UUID = UUID(), name: String, firstDay: Date, lastDay: Date, fromUntis: Bool? = nil) {
        self.id = id
        self.name = name
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.fromUntis = fromUntis
    }
}

/// One recorded Meldung. An activity count, never a grade.
public nonisolated struct ParticipationEntry: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var subjectID: UUID?
    public var lessonID: UUID?
    public var recordedAt: Date

    public init(id: UUID = UUID(), subjectID: UUID? = nil, lessonID: UUID? = nil, recordedAt: Date) {
        self.id = id
        self.subjectID = subjectID
        self.lessonID = lessonID
        self.recordedAt = recordedAt
    }
}

public nonisolated enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case german = "de"
    case english = "en"

    public var id: String { rawValue }

    /// Shown in its own language so users can always find theirs.
    public var nativeName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }
}

public nonisolated enum TaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case homework, todo
    public var id: String { rawValue }
}

public nonisolated enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, normal, high
    public var id: String { rawValue }
}

public nonisolated enum TaskRecurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case never, daily, weekdays, weekly, biweekly
    public var id: String { rawValue }
}

/// A Hausaufgabe or to-do. Named `SchoolTask` to stay clear of Swift's `Task`.
public nonisolated struct SchoolTask: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var title: String
    public var notes: String = ""
    public var kind: TaskKind = .homework
    public var subjectID: UUID?
    /// Due day (local midnight); `nil` for undated to-dos.
    public var dueDate: Date?
    public var completedAt: Date?
    public var priority: TaskPriority = .normal
    public var recurrence: TaskRecurrence = .never
    public var reminderAt: Date?
    public var updatedAt = Date()
    /// Homework imported from WebUntis; keeps it from being added twice.
    public var untisID: Int64?
    /// Assignment imported from Microsoft Teams (Graph id).
    public var teamsID: String?
    /// The recurring task whose completion created this one; reopening that task removes it again.
    public var spawnedFrom: UUID?

    public init(id: UUID = UUID(), title: String, notes: String = "", kind: TaskKind = .homework, subjectID: UUID? = nil, dueDate: Date? = nil, completedAt: Date? = nil, priority: TaskPriority = .normal, recurrence: TaskRecurrence = .never, reminderAt: Date? = nil, updatedAt: Date = Date(), untisID: Int64? = nil, teamsID: String? = nil, spawnedFrom: UUID? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.kind = kind
        self.subjectID = subjectID
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.priority = priority
        self.recurrence = recurrence
        self.reminderAt = reminderAt
        self.updatedAt = updatedAt
        self.untisID = untisID
        self.teamsID = teamsID
        self.spawnedFrom = spawnedFrom
    }

    public var isDone: Bool { completedAt != nil }
}

/// A scanned or imported exam (Klassenarbeit, Klausur, Test) stored as a PDF.
public nonisolated struct ExamDocument: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var title: String
    public var subjectID: UUID?
    public var date: Date
    /// Path inside Documents/Scans, e.g. "Mathematik/Exams/1. Klausur (12.10.2026).pdf".
    public var fileName: String
    public var pageCount: Int
    /// The grade as written by the teacher (e.g. "2-" or "11 P."), shown as-is.
    public var grade: String = ""
    public var notes: String = ""
    public var updatedAt = Date()
    /// `nil` in files from version 0.2, which only had exams.
    public var category: DocumentCategory?

    public init(id: UUID = UUID(), title: String, subjectID: UUID? = nil, date: Date, fileName: String, pageCount: Int, grade: String = "", notes: String = "", updatedAt: Date = Date(), category: DocumentCategory? = nil) {
        self.id = id
        self.title = title
        self.subjectID = subjectID
        self.date = date
        self.fileName = fileName
        self.pageCount = pageCount
        self.grade = grade
        self.notes = notes
        self.updatedAt = updatedAt
        self.category = category
    }

    public var kind: DocumentCategory { category ?? .exam }
}

/// What a scan is; also its folder in the Files app (English names, as shown there).
public nonisolated enum DocumentCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case exam, worksheet, document
    public var id: String { rawValue }

    public var folderName: String {
        switch self {
        case .exam: "Exams"
        case .worksheet: "Worksheets"
        case .document: "Documents"
        }
    }
}

/// Cards on the home screen; order and visibility are customizable.
public nonisolated enum DashboardCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, weekPreview, participation, streak, homework, exams, news, absences
    case nextLesson, weekChart, nextHoliday, todos, grades
    public var id: String { rawValue }
}

/// Cards on the Statistik tab.
public nonisolated enum StatsCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case perDay, bySubject, trend
    public var id: String { rawValue }
}

/// How much room a card takes, like tiles on a console home screen.
public nonisolated enum CardSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    public var id: String { rawValue }
}

/// A visible card and its size, in display order.
public nonisolated struct CardSlot<Kind: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var kind: Kind
    public var size: CardSize

    public init(kind: Kind, size: CardSize) {
        self.kind = kind
        self.size = size
    }
}

nonisolated extension CardSlot where Kind == DashboardCard {
    public static var defaultHome: [CardSlot<DashboardCard>] { [
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
    public static var defaultStats: [CardSlot<StatsCard>] { [
        .init(kind: .perDay, size: .medium),
        .init(kind: .bySubject, size: .medium),
        .init(kind: .trend, size: .large),
    ] }
}

/// Alternate app icons (work with free signing).
public nonisolated enum AppIconChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, orange, night
    public var id: String { rawValue }
    /// Asset catalog name for `setAlternateIconName`; `nil` is the default icon.
    public var assetName: String? {
        switch self {
        case .standard: nil
        case .orange: "AppIcon-Orange"
        case .night: "AppIcon-Night"
        }
    }
}

public nonisolated struct Preferences: Codable, Hashable, Sendable {
    public var language: AppLanguage = .german
    public var theme: AppTheme = .orange
    public var appearance: AppearanceChoice = .system
    /// Weekly Melde target; `nil` until the student sets or accepts one.
    public var weeklyGoal: Int?
    /// Any date in an A week; enables A/B-week lessons.
    public var weekAReference: Date?
    /// Ask "Hast du dich gemeldet?" after each lesson (local notification).
    public var askAfterLesson = false
    /// Show a Live Activity during lessons.
    public var liveActivities = true
    public var showMascot = true
    public var haptics = true
    /// Start screen cards with their sizes, in display order; missing cards are hidden.
    public var homeLayout: [CardSlot<DashboardCard>] = CardSlot<DashboardCard>.defaultHome
    /// Statistik cards with their sizes.
    public var statsLayout: [CardSlot<StatsCard>] = CardSlot<StatsCard>.defaultStats
    /// Parallel courses the student doesn't attend, as "weekday|start|subject".
    public var hiddenCourses: [String] = []
    public var gradeScale: GradeScaleChoice = .traditional
    /// Share of written grades in a subject average (the rest is oral).
    public var writtenWeight: Double = 0.5
    /// What + and − add or subtract on the 1–6 scale (e.g. 0.33 or 0.25).
    public var tendencyStep: Double = 0.33
    /// For the excuse note (Entschuldigung).
    public var studentName: String = ""
    public var className: String = ""
    public var excuseSalutation: String = ""
    public var adultStudent: Bool = false
    public var appIcon: AppIconChoice = .standard
    /// The start screen stops suggesting after-lesson check-ins once answered.
    public var checkInPromptDismissed = false
    /// The first-run tour was finished or skipped. Students who already have
    /// data never see it, so older files don't need this set.
    public var onboardingSeen = false
    /// Microsoft Teams stays hidden until the student turns it on: many schools must
    /// allow the app first (Microsoft admin consent).
    public var teamsEnabled = false
    /// The two places in the tab bar after Start and Stundenplan (feature ids).
    public var barTabs: [String] = ["tasks", "grades"]
    /// The tab Meldo opens on (feature id).
    public var startTab = "home"

    public init() {}

    public enum CodingKeys: String, CodingKey {
        case language, theme, appearance, weeklyGoal, weekAReference, askAfterLesson, liveActivities
        case showMascot, haptics, homeLayout, statsLayout, appIcon, checkInPromptDismissed, hiddenCourses, onboardingSeen, teamsEnabled, barTabs, startTab
        case gradeScale, writtenWeight, tendencyStep, studentName, className, excuseSalutation, adultStudent
        /// Read only, to migrate layouts from version 0.2.
        case dashboardCards
    }

    // Every field is optional when decoding, so files from older versions keep loading.
    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
public nonisolated struct UntisPeriodRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var date: Date
    public var startMinute: Int
    public var endMinute: Int
    public var subjectShort: String
    public var subjectLong: String
    public var teacher: String
    public var room: String?
    /// Planned room when the period moved (Raumänderung).
    public var originalRoom: String?
    public var cancelled: Bool
    /// Vertretung or extra period.
    public var irregular: Bool
    public var exam: Bool
    public var info: String?

    public init(id: Int64, date: Date, startMinute: Int, endMinute: Int, subjectShort: String, subjectLong: String, teacher: String, room: String? = nil, originalRoom: String? = nil, cancelled: Bool, irregular: Bool, exam: Bool, info: String? = nil) {
        self.id = id
        self.date = date
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.subjectShort = subjectShort
        self.subjectLong = subjectLong
        self.teacher = teacher
        self.room = room
        self.originalRoom = originalRoom
        self.cancelled = cancelled
        self.irregular = irregular
        self.exam = exam
        self.info = info
    }

    /// Matches `Subject.untisKey`.
    public var subjectKey: String { subjectShort.isEmpty ? subjectLong : subjectShort }
}

/// One period of the school's bell schedule; breaks are the gaps between them.
public nonisolated struct BellPeriod: Codable, Hashable, Sendable {
    public var name: String
    public var startMinute: Int
    public var endMinute: Int

    public init(name: String, startMinute: Int, endMinute: Int) {
        self.name = name
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

/// The weeks WebUntis lets the student see, refreshed on every import.
public nonisolated struct UntisTimetable: Codable, Hashable, Sendable {
    public var periods: [UntisPeriodRecord]
    public var firstDay: Date
    /// Last day WebUntis returned; schools can limit how far ahead students see.
    public var lastDay: Date
    public var bells: [BellPeriod]

    public init(periods: [UntisPeriodRecord], firstDay: Date, lastDay: Date, bells: [BellPeriod]) {
        self.periods = periods
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.bells = bells
    }
}

/// An absence from the WebUntis class register.
public nonisolated struct UntisAbsenceRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var firstDay: Date
    public var lastDay: Date
    public var startMinute: Int
    public var endMinute: Int
    public var reason: String
    public var text: String
    public var excused: Bool

    public init(id: Int64, firstDay: Date, lastDay: Date, startMinute: Int, endMinute: Int, reason: String, text: String, excused: Bool) {
        self.id = id
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.reason = reason
        self.text = text
        self.excused = excused
    }
}

/// An exam WebUntis lists for the student (Klausur, Test).
public nonisolated struct UntisExamRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var date: Date
    public var startMinute: Int
    public var endMinute: Int
    public var subject: String
    public var name: String
    public var examType: String
    public var teachers: [String]
    public var rooms: [String]
    public var text: String

    public init(id: Int64, date: Date, startMinute: Int, endMinute: Int, subject: String, name: String, examType: String, teachers: [String], rooms: [String], text: String) {
        self.id = id
        self.date = date
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.subject = subject
        self.name = name
        self.examType = examType
        self.teachers = teachers
        self.rooms = rooms
        self.text = text
    }
}

/// A message of the day from the school.
public nonisolated struct UntisNewsRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var subject: String
    public var text: String

    public init(id: Int64, subject: String, text: String) {
        self.id = id
        self.subject = subject
        self.text = text
    }
}

/// Data from the WebUntis web API, refreshed on every import. Each list stays
/// empty when the school hides it.
public nonisolated struct UntisExtras: Codable, Hashable, Sendable {
    public var absences: [UntisAbsenceRecord] = []
    public var exams: [UntisExamRecord] = []
    public var news: [UntisNewsRecord] = []
    public var updated: Date

    public init(absences: [UntisAbsenceRecord] = [], exams: [UntisExamRecord] = [], news: [UntisNewsRecord] = [], updated: Date) {
        self.absences = absences
        self.exams = exams
        self.news = news
        self.updated = updated
    }
}

/// One grade the student enters (Klausur, Test, mündliche Note). Grades are
/// the student's own record for estimating averages, never official.
public nonisolated struct GradeEntry: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var subjectID: UUID
    /// 1.0–6.0 (traditional, tendency already applied) or 0–15 points.
    public var value: Double
    public var written: Bool
    public var weight: Double = 1
    public var title: String = ""
    public var date: Date

    public init(id: UUID = UUID(), subjectID: UUID, value: Double, written: Bool, weight: Double = 1, title: String = "", date: Date) {
        self.id = id
        self.subjectID = subjectID
        self.value = value
        self.written = written
        self.weight = weight
        self.title = title
        self.date = date
    }
}

/// How grades are entered and averaged. Configuration, not constants: schools differ.
public nonisolated enum GradeScaleChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 1 (best) to 6.
    case traditional
    /// 15 (best) to 0, Oberstufe.
    case points
    public var id: String { rawValue }
}

/// The Microsoft Teams connection. The refresh token lives in the Keychain.
public nonisolated struct TeamsLink: Codable, Hashable, Sendable {
    public var account: String
    public var lastSync: Date?

    public init(account: String, lastSync: Date? = nil) {
        self.account = account
        self.lastSync = lastSync
    }
}

/// Everything persisted on device. Versioned so later migrations can import it.
public nonisolated struct AppData: Codable, Sendable {
    /// 2: adds tasks and exams.
    public static let currentSchemaVersion = 2

    public var schemaVersion = AppData.currentSchemaVersion
    public var subjects: [Subject] = []
    public var lessons: [Lesson] = []
    public var holidays: [Holiday] = []
    public var participation: [ParticipationEntry] = []
    public var tasks: [SchoolTask] = []
    public var exams: [ExamDocument] = []
    public var changes: [TimetableChangeRecord] = []
    public var untis: UntisLink?
    public var untisTimetable: UntisTimetable?
    public var untisExtras: UntisExtras?
    public var teams: TeamsLink?
    public var grades: [GradeEntry] = []
    public var preferences = Preferences()
    /// Imported WebUntis homework ("untis:<id>") and Teams assignments ("teams:<id>")
    /// the student deleted, so the next sync doesn't bring them back.
    public var dismissedImports: Set<String> = []
    /// What changed when, for sync (see `SyncMerge`).
    public var sync = SyncLedger()

    public init() {}

    // Missing collections decode as empty, so version-1 files load unchanged.
    public init(from decoder: Decoder) throws {
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
