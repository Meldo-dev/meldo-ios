import Foundation
import MeldoState
import MeldoUI
import Observation
import MeldeCore
import MeldoKit

/// WebUntis import: fetch this week and the next, let Rust derive
/// subjects, weekly lessons and changes, then merge into the student's data.
/// WebUntis update status on this device.
@Observable
final class UntisSession {
    /// A WebUntis update is running; automatic updates don't start a second one.
    var isRefreshing = false
    /// After a failed automatic update, the next one waits until then (see refreshUntisIfStale).
    @ObservationIgnored var retryAfter: Date?
    @ObservationIgnored var failures = 0
    /// Bumped by "WebUntis trennen". An import that started earlier stops writing,
    /// so it can't bring back the connection or its secret.
    @ObservationIgnored var generation = 0
}

extension AppModel {
    var untisSession: UntisSession { moduleState(UntisSession.init) }
    var isRefreshingUntis: Bool { get { untisSession.isRefreshing } set { untisSession.isRefreshing = newValue } }
    var untisRetryAfter: Date? { get { untisSession.retryAfter } set { untisSession.retryAfter = newValue } }
    var untisFailures: Int { get { untisSession.failures } set { untisSession.failures = newValue } }
    var untisGeneration: Int { get { untisSession.generation } set { untisSession.generation = newValue } }

    /// Keeps the web login out of backups, and forgets this device's secrets when the
    /// connection was removed or switched on another device.
    func installUntis() {
        if hasReadableStore { UntisSilentLogin.keepWebLoginOutOfBackups() }
        onMerge { [weak self] before in
            guard let self, let untis = before.untis else { return }
            if let now = data.untis {
                // Another account or server now: the old account's secret goes (and imports still
                // running for it stop, so they can't store it again), the new login stays.
                if Self.keychainAccount(now) != Self.keychainAccount(untis) { forgetUntisSecrets(untis) }
            } else {
                forgetUntisSecrets(untis)
            }
        }
    }

    /// Remembered for the next Entschuldigung.
    func setExcuseDetails(name: String, className: String, salutation: String, adult: Bool) {
        mutate { data in
            data.preferences.studentName = name.trimmingCharacters(in: .whitespaces)
            data.preferences.className = className.trimmingCharacters(in: .whitespaces)
            data.preferences.excuseSalutation = salutation.trimmingCharacters(in: .whitespaces)
            data.preferences.adultStudent = adult
        }
    }

    struct UntisImportSummary: Equatable {
        var newSubjects = 0
        var lessons = 0
        var changes = 0
        var skippedExtra = 0
        var holidays = 0
    }

    /// "server|school|user", the key it always had. A name containing "|" could make two
    /// accounts share it, so those get an escaped key in their own "server#…" form.
    static func keychainAccount(_ link: UntisLink) -> String {
        guard link.loginName.contains("|") || link.user.contains("|") else {
            return "\(link.server)|\(link.loginName)|\(link.user)"
        }
        func part(_ text: String) -> String {
            text.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "|", with: "%7C")
        }
        return "\(link.server)#\(part(link.loginName))|\(part(link.user))"
    }

    var untisLink: UntisLink? { data.untis }

    /// Logs in, imports, and remembers the connection (password → Keychain).
    func connectUntis(school: FfiUntisSchool, user: String, password: String) async throws(UntisClient.Failure) -> UntisImportSummary {
        // A new login stops a refresh still running for the old connection.
        untisGeneration += 1
        let generation = untisGeneration
        let link = UntisLink(server: school.server, loginName: school.loginName, schoolName: school.displayName, user: user)
        let summary = try await importFromUntis(link: link, password: password, generation: generation)
        try ensureUntisCurrent(generation)
        _ = Keychain.save(password, account: Self.keychainAccount(link))
        return summary
    }

    /// Imports with a session the student logged in to on the school's own login
    /// page (Microsoft 365, IServ, …) inside Meldo. `cookies` is the `Cookie`
    /// header for the WebUntis server; Meldo never sees the school password.
    /// `server` is the WebUntis host the login ended on, which can differ from the search result.
    func connectUntisWithBrowser(school: FfiUntisSchool, server: String, cookies: String, sessionID: String,
                                 ssoPath: String? = nil) async throws(UntisClient.Failure) -> UntisImportSummary {
        untisGeneration += 1
        let generation = untisGeneration
        let previous = data.untis
        // Keep a renewal link learned earlier when this login didn't pass one (e.g. the SSO was remembered).
        let learned = ssoPath ?? (data.untis?.server == server ? data.untis?.ssoPath : nil)
        let link = UntisLink(server: server, loginName: school.loginName, schoolName: school.displayName,
                             user: "", browserLogin: true, ssoPath: learned)
        let client = UntisClient(browserCookies: cookies)
        let auth = try await client.browserAuth(server: link.server, sessionID: sessionID)
        let summary = try await importFromUntis(link: link, client: client, auth: auth, logout: false, generation: generation)
        try ensureUntisCurrent(generation)
        // A login that ended on another server leaves no secret behind for the old one.
        if let previous, Self.keychainAccount(previous) != Self.keychainAccount(link) {
            Keychain.delete(account: Self.keychainAccount(previous))
        }
        _ = Keychain.save(cookies, account: Self.keychainAccount(link))
        UntisSilentLogin.keepWebLoginOutOfBackups()
        return summary
    }

    /// Re-imports with the stored password or school-login session. Returns nil
    /// when not connected; a school-login session that ran out throws `.sessionExpired`.
    @discardableResult
    func refreshUntis() async throws(UntisClient.Failure) -> UntisImportSummary? {
        guard let link = data.untis else { return nil }
        let generation = untisGeneration
        let secret = Keychain.read(account: Self.keychainAccount(link))
        if link.browserLogin == true {
            // No session stored on this device (restored from a backup or moved to a new
            // iPhone): the school login must be done here, not replayed from restored cookies.
            guard let secret else { throw .sessionExpired }
            do {
                let client = UntisClient(browserCookies: secret)
                let auth = try await client.browserAuth(server: link.server, sessionID: Self.sessionID(in: secret) ?? "")
                return try await importFromUntis(link: link, client: client, auth: auth, logout: false, generation: generation)
            } catch .sessionExpired {
                // Renewed below.
            }
            // The WebUntis session ran out (they last hours, not weeks): sign in again
            // through the school's login in the background, which usually remembers
            // the student. Only when the school asks for the password again does the
            // student see "log in again".
            try ensureUntisCurrent(generation)
            let renewed = await UntisSilentLogin.renew(server: link.server, loginName: link.loginName, ssoPath: link.ssoPath)
            guard generation == untisGeneration else {
                // "Trennen" ran while the hidden web view was signing in: wipe what it stored.
                await UntisSilentLogin.forgetWebLogin()
                throw .noAccess("disconnected")
            }
            guard let renewed else { throw .sessionExpired }
            var renewedLink = link
            renewedLink.server = renewed.server
            let client = UntisClient(browserCookies: renewed.cookies)
            let auth = try await client.browserAuth(server: renewed.server, sessionID: renewed.sessionID)
            let summary = try await importFromUntis(link: renewedLink, client: client, auth: auth, logout: false, generation: generation)
            try ensureUntisCurrent(generation)
            if renewedLink.server != link.server { Keychain.delete(account: Self.keychainAccount(link)) }
            _ = Keychain.save(renewed.cookies, account: Self.keychainAccount(renewedLink))
            return summary
        }
        guard let secret else { return nil }
        return try await importFromUntis(link: link, password: secret, generation: generation)
    }

    /// The `JSESSIONID` value in a `Cookie` header.
    static func sessionID(in cookies: String) -> String? {
        cookies.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("JSESSIONID=") }
            .map { String($0.dropFirst("JSESSIONID=".count)) }
    }

    /// How old WebUntis data may get while the app is open: just under the 30-second loop, so each tick updates.
    static let untisRefreshInterval: TimeInterval = 25

    /// How old it may get in the background: a little under the 20-minute rhythm, so an early wake-up still updates.
    static let untisBackgroundRefreshInterval: TimeInterval = 18 * 60

    /// Automatic update: when the app opens, every 30 seconds while it's open
    /// and about every 20 minutes in the background (Background App Refresh). Silent on failure.
    func refreshUntisIfStale(maxAge: TimeInterval = AppModel.untisRefreshInterval) async {
        guard !isRefreshingUntis, let link = data.untis else { return }
        // A "last update" in the future (clock changed, another device) doesn't block updates.
        if let last = link.lastSync, (0..<maxAge).contains(currentDate.timeIntervalSince(last)) { return }
        // After a failure it waits, so a wrong password isn't sent to the school every 30 seconds.
        if let after = untisRetryAfter, currentDate < after { return }
        isRefreshingUntis = true
        defer { isRefreshingUntis = false }
        do {
            _ = try await refreshUntis()
        } catch {
            untisFailures += 1
            let delay = Self.untisRetryDelay(after: error, failures: untisFailures)
            untisRetryAfter = delay.isFinite ? currentDate.addingTimeInterval(delay) : .distantFuture
        }
    }

    /// How long automatic updates pause after a failure. A wrong password stops them until
    /// the next manual update or connect (schools can lock accounts after failed logins);
    /// an expired school login or holidays wait 30 minutes; other errors back off from one minute.
    static func untisRetryDelay(after failure: UntisClient.Failure, failures: Int) -> TimeInterval {
        switch failure {
        case .wrongCredentials: .infinity
        case .sessionExpired, .noLessons: 30 * 60
        default: min(60 * pow(2, Double(min(failures, 6) - 1)), 30 * 60)
        }
    }

    /// Forgets the connection and the password. Imported lessons stay as normal lessons.
    func disconnectUntis() {
        if let link = data.untis { forgetUntisSecrets(link) }
        mutate { data in
            data.untis = nil
            data.untisTimetable = nil
            data.untisExtras = nil
            data.changes.removeAll { $0.fromUntis == true }
            for i in data.lessons.indices { data.lessons[i].fromUntis = nil }
        }
    }

    /// Deletes the stored password or session and the web views' school login, and
    /// stops imports that are still running.
    func forgetUntisSecrets(_ link: UntisLink) {
        untisGeneration += 1
        Keychain.delete(account: Self.keychainAccount(link))
        Task { await UntisSilentLogin.forgetWebLogin() }
    }

    /// Throws when "WebUntis trennen" ran after the import with this generation started.
    private func ensureUntisCurrent(_ generation: Int) throws(UntisClient.Failure) {
        guard generation == untisGeneration else { throw .noAccess("disconnected") }
    }

    private func importFromUntis(link: UntisLink, password: String, generation: Int) async throws(UntisClient.Failure) -> UntisImportSummary {
        let client = UntisClient()
        let auth = try await client.login(server: link.server, loginName: link.loginName, user: link.user, password: password)
        return try await importFromUntis(link: link, client: client, auth: auth, logout: true, generation: generation)
    }

    /// `logout` ends password sessions; school-login sessions stay open so the
    /// next refresh can reuse them.
    private func importFromUntis(link: UntisLink, client: UntisClient, auth: FfiUntisAuth, logout: Bool, generation: Int) async throws(UntisClient.Failure) -> UntisImportSummary {
        let today = FfiDate(currentDate, calendar: calendar)
        guard let thisWeek = try? untisWeekStart(date: today),
              let thisMonday = thisWeek.date(in: calendar),
              let lastDay = calendar.date(byAdding: .day, value: 8 * 7 - 1, to: thisMonday),
              let historyMonday = calendar.date(byAdding: .day, value: -Self.untisHistoryWeeks * 7, to: thisMonday) else { throw .noAccess("date") }
        // Past weeks too: with only the next two weeks (e.g. after the holidays) every
        // one-off difference looked like an A/B week.
        let historyWeek = FfiDate(historyMonday, calendar: calendar)
        // Holidays and the bell schedule are a bonus: an import still works
        // when a school hides them.
        let holidays = (try? await client.holidays(server: link.server, loginName: link.loginName)) ?? []
        let bells = (try? await client.timegrid(server: link.server, loginName: link.loginName)) ?? []
        // Eight weeks in one request. Schools can limit how far ahead students
        // see; then WebUntis refuses the request, so ask for fewer weeks.
        var body = ""
        var fetchedFirst = historyWeek
        var fetchedLastDay = lastDay
        attempts: for first in [historyWeek, thisWeek] {
            for weeks in [8, 4, 2, 1] {
                guard let last = calendar.date(byAdding: .day, value: weeks * 7 - 1, to: thisMonday) else { continue }
                body = try await client.timetable(
                    server: link.server, loginName: link.loginName, auth: auth,
                    first: first, last: FfiDate(last, calendar: calendar)
                )
                fetchedFirst = first
                fetchedLastDay = last
                if (try? untisParsePeriods(timetableBody: body)) != nil { break attempts }
            }
        }
        try ensureUntisCurrent(generation)
        if let periods = try? untisParsePeriods(timetableBody: body), let firstDay = fetchedFirst.date(in: calendar) {
            storeUntisWeeks(periods, bells: bells, firstDay: firstDay, lastDay: Self.visibleUntil(periods, requested: fetchedLastDay, from: thisMonday, calendar: calendar))
        }
        let outcome: Result<UntisImportSummary, UntisClient.Failure>
        do {
            outcome = .success(try importSchedule(link: link, body: body, from: thisWeek, holidays: holidays))
        } catch {
            outcome = .failure(error)
        }
        // After the subjects exist (applyUntis), so homework finds the subject it belongs to;
        // also when the weeks hold no lessons, so absences and homework stay current.
        await importUntisExtras(client: client, server: link.server, auth: auth, generation: generation)
        if logout { await client.logout(server: link.server, loginName: link.loginName) }
        try ensureUntisCurrent(generation)
        return try outcome.get()
    }

    #if DEBUG
    /// UI-test mode only: runs a recorded WebUntis answer through the same parsing
    /// and merge steps as `syncUntis`, without a network or a login.
    func importUntisSample(link: UntisLink, body: String, bells: [FfiTimeUnit], holidays: [FfiUntisHoliday],
                           absences: [FfiUntisAbsence], exams: [FfiUntisExam], homework: [FfiUntisHomework], news: [FfiUntisNews]) {
        guard let thisWeek = try? untisWeekStart(date: FfiDate(currentDate, calendar: calendar)),
              let monday = thisWeek.date(in: calendar),
              let last = calendar.date(byAdding: .day, value: 13, to: monday),
              let periods = try? untisParsePeriods(timetableBody: body) else { return }
        storeUntisWeeks(periods, bells: bells, firstDay: monday, lastDay: last)
        _ = try? importSchedule(link: link, body: body, from: thisWeek, holidays: holidays)
        applyUntisExtras(absences: absences, exams: exams, homework: homework, news: news)
    }
    #endif

    static let untisHistoryWeeks = 4

    /// The end of the last week WebUntis actually sent lessons for. Schools can hide
    /// weeks ahead: WebUntis then answers with nothing instead of an error, and those
    /// weeks must show as hidden, not as empty.
    /// Only lessons from `from` (this week) on count: in the summer holidays WebUntis sends
    /// nothing ahead, and those weeks are holidays, not hidden.
    static func visibleUntil(_ periods: [FfiUntisPeriod], requested: Date, from: Date, calendar: Calendar) -> Date {
        guard let last = periods.compactMap({ $0.date.date(in: calendar) }).max(), last >= from else { return requested }
        let sunday = calendar.date(byAdding: .day, value: 6 - calendar.mondayIndex(of: last), to: last) ?? last
        return min(sunday, requested)
    }

    /// Derives the weekly plan from the dated periods and applies it.
    private func importSchedule(link: UntisLink, body: String, from thisWeek: FfiDate, holidays: [FfiUntisHoliday]) throws(UntisClient.Failure) -> UntisImportSummary {
        let schedule: FfiUntisSchedule
        let monday: Date
        do {
            // Week A is the current teaching week; earlier weeks are history that only
            // confirms A/B. Only history (holidays until the end of the window) still works.
            guard let firstWeek = try untisFirstTeachingWeek(timetableBody: body, from: thisWeek)
                    ?? untisFirstTeachingWeek(timetableBody: body, from: FfiDate(year: 2000, month: 1, day: 1)),
                  let firstMonday = firstWeek.date(in: calendar) else {
                // Never replace the timetable with an empty one; keep the holidays.
                applyUntisHolidays(holidays)
                throw UntisClient.Failure.noLessons
            }
            schedule = try untisDeriveSchedule(timetableBody: body, weekAStart: firstWeek)
            monday = firstMonday
        } catch let failure as UntisClient.Failure {
            throw failure
        } catch let MeldeError.UntisServer(code, message) {
            throw code == -8520 ? (link.browserLogin == true ? .sessionExpired : .wrongCredentials)
                : .server(code: code, message: message)
        } catch {
            throw .noAccess("\(error)")
        }
        applyUntisHolidays(holidays)
        var syncedLink = link
        syncedLink.lastSync = currentDate
        untisFailures = 0
        untisRetryAfter = nil
        var summary = applyUntis(schedule, weekAStart: monday, link: syncedLink)
        summary.holidays = holidays.count
        return summary
    }

    /// Absences (this school year), exams (next four months), homework (two
    /// weeks back to eight ahead) and today's school messages. Each part is
    /// optional: schools decide what students may see.
    private func importUntisExtras(client: UntisClient, server: String, auth: FfiUntisAuth, generation: Int) async {
        let calendar = calendar
        let today = calendar.startOfDay(for: currentDate)
        let year = calendar.component(.year, from: today) - (calendar.component(.month, from: today) < 8 ? 1 : 0)
        let schoolYearStart = calendar.date(from: DateComponents(year: year, month: 8, day: 1)) ?? today
        func day(_ offset: Int) -> FfiDate {
            FfiDate(calendar.date(byAdding: .day, value: offset, to: today) ?? today, calendar: calendar)
        }
        let todayFfi = FfiDate(today, calendar: calendar)
        let absences = try? await client.absences(server: server, auth: auth, first: FfiDate(schoolYearStart, calendar: calendar), last: todayFfi)
        // Some schools refuse the exam list to students but mark exams in the timetable.
        // From the start of the timetable history, so past weeks keep their exam marks;
        // lists only show upcoming exams.
        let examsFrom = day(-Self.untisHistoryWeeks * 7)
        var exams = try? await client.exams(server: server, auth: auth, first: examsFrom, last: day(120))
        if exams == nil {
            exams = try? await client.timetableExams(server: server, auth: auth, first: examsFrom, last: day(120))
        }
        let homework = try? await client.homework(server: server, first: day(-14), last: day(56))
        let news = try? await client.news(server: server, date: todayFfi)
        guard generation == untisGeneration else { return }
        applyUntisExtras(absences: absences, exams: exams, homework: homework, news: news)
    }

    /// Stores what `importUntisExtras` fetched; `nil` means the school refused that part.
    func applyUntisExtras(absences: [FfiUntisAbsence]?, exams: [FfiUntisExam]?, homework: [FfiUntisHomework]?, news: [FfiUntisNews]?) {
        let calendar = calendar
        let previous = data.untisExtras
        var extras = UntisExtras(updated: currentDate)
        extras.absences = absences.map { list in
            list.compactMap { a -> UntisAbsenceRecord? in
                guard let first = a.firstDay.date(in: calendar), let last = a.lastDay.date(in: calendar) else { return nil }
                return UntisAbsenceRecord(id: a.id, firstDay: first, lastDay: last,
                                          startMinute: Int(a.startMinute), endMinute: Int(a.endMinute),
                                          reason: a.reason, text: a.text, excused: a.excused)
            }
        } ?? previous?.absences ?? []
        extras.exams = exams.map { list in
            list.compactMap { e -> UntisExamRecord? in
                guard let date = e.date.date(in: calendar) else { return nil }
                return UntisExamRecord(id: e.id, date: date, startMinute: Int(e.startMinute), endMinute: Int(e.endMinute),
                                       subject: e.subject, name: e.name, examType: e.examType,
                                       teachers: e.teachers, rooms: e.rooms, text: e.text)
            }
        } ?? previous?.exams ?? []
        extras.news = news.map { list in list.map { UntisNewsRecord(id: $0.id, subject: $0.subject, text: $0.text) } } ?? []
        let tasks = (homework ?? []).compactMap { h -> SchoolTask? in
            guard let due = h.due.date(in: calendar) else { return nil }
            let subject = data.subjects.first { $0.untisKey == h.subject || $0.name == h.subject }
            let title = h.text.isEmpty ? h.remark : h.text
            guard !title.isEmpty else { return nil }
            // Done in WebUntis: count it as done on time, not as finished today.
            return SchoolTask(title: title, notes: h.text.isEmpty ? "" : h.remark, kind: .homework,
                              subjectID: subject?.id, dueDate: due,
                              completedAt: h.completed ? min(due, currentDate) : nil, untisID: h.id)
        }
        mutate { data in
            data.untisExtras = extras
            // New WebUntis homework only; what the student already has stays as they left it.
            let known = Set(data.tasks.compactMap(\.untisID))
            data.tasks.append(contentsOf: tasks.filter { task in
                guard let id = task.untisID else { return false }
                return !known.contains(id) && !data.dismissedImports.contains("untis:\(id)")
            })
            // Homework imported before its subject existed gets it now; a subject the student set stays.
            let subjects = Dictionary(tasks.compactMap { t in t.untisID.map { ($0, t.subjectID) } }, uniquingKeysWith: { first, _ in first })
            for i in data.tasks.indices where data.tasks[i].subjectID == nil {
                if let id = data.tasks[i].untisID, let subject = subjects[id] { data.tasks[i].subjectID = subject }
            }
        }
    }

    /// Keeps the dated periods for the Untis-style timetable. `lastDay` is the
    /// end of the window WebUntis accepted, so a school's look-ahead limit shows.
    func storeUntisWeeks(_ periods: [FfiUntisPeriod], bells: [FfiTimeUnit], firstDay: Date, lastDay: Date) {
        let calendar = calendar
        let records = periods.compactMap { p -> UntisPeriodRecord? in
            guard let date = p.date.date(in: calendar) else { return nil }
            return UntisPeriodRecord(
                id: p.id, date: date, startMinute: Int(p.startMinute), endMinute: Int(p.endMinute),
                subjectShort: p.subjectShort, subjectLong: p.subjectLong, teacher: p.teacher,
                room: p.room, originalRoom: p.originalRoom,
                cancelled: p.cancelled, irregular: p.irregular, exam: p.exam, info: p.info
            )
        }
        let bellPeriods = bells.map { BellPeriod(name: $0.name, startMinute: Int($0.startMinute), endMinute: Int($0.endMinute)) }
        mutate { data in
            data.untisTimetable = UntisTimetable(
                periods: records, firstDay: firstDay, lastDay: lastDay,
                bells: bellPeriods.isEmpty ? (data.untisTimetable?.bells ?? []) : bellPeriods
            )
        }
    }

    /// Replaces the holidays from an earlier WebUntis import; ones the student
    /// added by hand stay.
    func applyUntisHolidays(_ holidays: [FfiUntisHoliday]) {
        guard !holidays.isEmpty else { return }
        let calendar = calendar
        // WebUntis sends every holiday since the school started using it (often ten
        // years, with duplicates) and splits Ferien into single days. Keep this school
        // year on, and join days of the same Ferien into one entry.
        let today = calendar.startOfDay(for: currentDate)
        let year = calendar.component(.year, from: today) - (calendar.component(.month, from: today) < 8 ? 1 : 0)
        let schoolYearStart = calendar.date(from: DateComponents(year: year, month: 8, day: 1)) ?? today
        var merged: [Holiday] = []
        let ranges = holidays.compactMap { h -> (String, Date, Date)? in
            guard let first = h.firstDay.date(in: calendar), let last = h.lastDay.date(in: calendar),
                  last >= schoolYearStart else { return nil }
            return (h.name.trimmingCharacters(in: .whitespaces), first, max(first, last))
        }.sorted { ($0.1, $0.2) < ($1.1, $1.2) }
        for (name, first, last) in ranges {
            if let i = merged.lastIndex(where: { $0.name == name }),
               let dayAfter = calendar.date(byAdding: .day, value: 1, to: merged[i].lastDay), first <= dayAfter {
                merged[i].lastDay = max(merged[i].lastDay, last)
            } else {
                merged.append(Holiday(name: name, firstDay: first, lastDay: last, fromUntis: true))
            }
        }
        mutate { data in
            data.holidays.removeAll { $0.fromUntis == true }
            data.holidays.append(contentsOf: merged)
            data.holidays.sort { $0.firstDay < $1.firstDay }
        }
    }

    /// Merges an Untis schedule. Existing subjects are matched by Untis key or
    /// name; existing lessons in the same slot keep their id (and Meldungen).
    func applyUntis(_ schedule: FfiUntisSchedule, weekAStart: Date, link: UntisLink) -> UntisImportSummary {
        var summary = UntisImportSummary(changes: schedule.changes.count, skippedExtra: Int(schedule.skippedExtra))
        let now = currentDate
        let calendar = calendar
        // Rust labels the first imported week A; a reference the student already set wins.
        let importWeekIsB = data.preferences.weekAReference != nil && !isWeekA(weekAStart)
        mutate { data in
            // Subjects.
            var subjectByKey: [String: UUID] = [:]
            for (index, s) in schedule.subjects.enumerated() {
                if let i = data.subjects.firstIndex(where: { $0.untisKey == s.key })
                    ?? data.subjects.firstIndex(where: {
                        $0.name.compare(s.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                            || (!s.shortName.isEmpty && $0.shortName.caseInsensitiveCompare(s.shortName) == .orderedSame)
                    }) {
                    data.subjects[i].untisKey = s.key
                    subjectByKey[s.key] = data.subjects[i].id
                } else {
                    let subject = Subject(
                        name: s.name, shortName: s.shortName,
                        color: SubjectColor.allCases[(data.subjects.count + index) % SubjectColor.allCases.count],
                        symbolName: SubjectSymbols.guess(for: s.name),
                        updatedAt: now, untisKey: s.key
                    )
                    data.subjects.append(subject)
                    subjectByKey[s.key] = subject.id
                    summary.newSubjects += 1
                }
            }

            // Lessons: reuse ids of lessons in the same slot, replace earlier Untis lessons.
            var kept: Set<UUID> = []
            var lessonByKeySlot: [String: UUID] = [:]
            for l in schedule.lessons {
                guard let subjectID = subjectByKey[l.subjectKey] else { continue }
                let weekday = l.weekday.mondayIndex
                let parity: WeekParity = switch l.parity {
                case .every: .every
                case .a: importWeekIsB ? .b : .a
                case .b: importWeekIsB ? .a : .b
                }
                let existing = data.lessons.firstIndex {
                    $0.weekday == weekday && $0.startMinute == Int(l.startMinute) && $0.subjectID == subjectID
                }
                let id = existing.map { data.lessons[$0].id } ?? UUID()
                let lesson = Lesson(
                    id: id, subjectID: subjectID, weekday: weekday,
                    startMinute: Int(l.startMinute), endMinute: Int(l.endMinute),
                    parity: parity, room: l.room ?? "", updatedAt: now, fromUntis: true
                )
                if let existing { data.lessons[existing] = lesson } else { data.lessons.append(lesson) }
                kept.insert(id)
                lessonByKeySlot["\(l.subjectKey)|\(weekday)|\(l.startMinute)"] = id
            }
            let removed = Set(data.lessons.filter { $0.fromUntis == true && !kept.contains($0.id) }.map(\.id))
            data.lessons.removeAll { removed.contains($0.id) }
            for i in data.participation.indices where data.participation[i].lessonID.map(removed.contains) == true {
                data.participation[i].lessonID = nil
            }
            summary.lessons = kept.count

            // Changes: replace earlier Untis changes.
            data.changes.removeAll { $0.fromUntis == true || removed.contains($0.lessonID) }
            for c in schedule.changes {
                guard let day = c.date.date(in: calendar) else { continue }
                let weekday = calendar.mondayIndex(of: day)
                guard let lessonID = lessonByKeySlot["\(c.subjectKey)|\(weekday)|\(c.startMinute)"] else { continue }
                switch c.kind {
                case .cancelled:
                    data.changes.append(TimetableChangeRecord(lessonID: lessonID, date: day, kind: .cancelled, fromUntis: true))
                case .substituted(let subjectKey, let room):
                    data.changes.append(TimetableChangeRecord(
                        lessonID: lessonID, date: day, kind: .substituted,
                        substituteSubjectID: subjectKey.flatMap { subjectByKey[$0] }, room: room, fromUntis: true
                    ))
                }
            }

            // A/B weeks: the first imported week is week A when lessons alternate.
            if schedule.lessons.contains(where: { $0.parity != .every }), data.preferences.weekAReference == nil {
                data.preferences.weekAReference = weekAStart
            }
            data.untis = link
        }
        return summary
    }
}

/// SF Symbol guesses for common German subject names.
enum SubjectSymbols {
    static func guess(for name: String) -> String {
        let n = name.lowercased()
        let table: [(String, String)] = [
            ("mathe", "function"), ("deutsch", "text.book.closed"), ("englisch", "character.book.closed"),
            ("franz", "character.book.closed"), ("latein", "building.columns"), ("spanisch", "character.book.closed"),
            ("physik", "atom"), ("chemie", "flask"), ("bio", "leaf"), ("geschicht", "building.columns"),
            ("erdkunde", "globe.europe.africa"), ("geograph", "globe.europe.africa"), ("politik", "scalemass"),
            ("sozial", "scalemass"), ("wirtschaft", "chart.line.uptrend.xyaxis"), ("kunst", "paintpalette"),
            ("musik", "music.note"), ("sport", "figure.run"), ("religion", "hands.and.sparkles"),
            ("ethik", "hands.and.sparkles"), ("philosoph", "theatermasks"), ("informatik", "laptopcomputer"),
            ("theater", "theatermasks"),
        ]
        return table.first { n.contains($0.0) }?.1 ?? "book.closed"
    }
}
