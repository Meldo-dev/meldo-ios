import Foundation
import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI

extension AppModel {
    /// The model for this launch. Debug builds started by the UI tests with
    /// `-uitest` get an in-memory store, a fixed clock and optional sample data,
    /// so screenshots are reproducible and real data is never touched.
    /// Release builds (the IPA) always use the real store.
    static func makeForLaunch() -> AppModel {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest") {
            return UITestLaunch(arguments: args).makeModel().installingModules()
        }
        #endif
        return AppModel(store: try? LocalStore.standard()).installingModules()
    }

    /// Connects the modules to a new model. Keychain items outlive the app, so a fresh
    /// install first forgets what an earlier one left behind.
    func installingModules() -> AppModel {
        if hasReadableStore {
            Keychain.forgetEarlierInstall(hasConnection: data.untis != nil || data.teams != nil,
                                          alwaysForget: AppModel.perInstallSecrets)
        }
        installUntis()
        installTeams()
        installDrive()
        return self
    }
}

#if DEBUG
/// Launch options understood in UI-test mode:
/// `-uitest-now 2026-10-19T08:10` (local time), `-uitest-seed`,
/// `-uitest-untis` (recorded WebUntis answers instead of own lessons),
/// `-uitest-language de|tr|en`, `-uitest-theme <AppTheme>`,
/// `-uitest-onboarding` (show the first-run tour; hidden otherwise so other tests start on Start).
private struct UITestLaunch {
    let arguments: [String]

    func value(_ flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    var now: Date {
        let calendar = Calendar.current
        guard let raw = value("-uitest-now") else { return Date() }
        let parts = raw.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard parts.count == 5 else { return Date() }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])) ?? Date()
    }

    func makeModel() -> AppModel {
        let fixed = now
        let model = AppModel(store: nil, now: { fixed })
        if let language = value("-uitest-language").flatMap(AppLanguage.init(rawValue:)) {
            model.setLanguage(language)
        }
        if let raw = value("-uitest-theme") {
            if let appearance = AppearanceChoice(rawValue: raw) {
                model.setAppearance(appearance)
            }
        }
        if arguments.contains("-uitest-untis") {
            UntisSampleData.seed(model, now: fixed)
        } else if arguments.contains("-uitest-seed") {
            SampleData.seed(model, now: fixed)
        }
        if !arguments.contains("-uitest-onboarding") {
            model.finishOnboarding()
        }
        return model
    }
}

/// A realistic school week for screenshots: five subjects, a full timetable,
/// three weeks of Meldungen, homework and a weekly goal.
private enum SampleData {
    static func seed(_ model: AppModel, now: Date) {
        let calendar = Calendar.current
        let subjects: [Subject] = [
            Subject(name: "Mathematik", shortName: "M", color: .blue, symbolName: "function", teacher: "Fr. Weber"),
            Subject(name: "Deutsch", shortName: "D", color: .red, symbolName: "text.book.closed", teacher: "Hr. Schulz"),
            Subject(name: "Englisch", shortName: "E", color: .purple, symbolName: "character.book.closed"),
            Subject(name: "Biologie", shortName: "Bio", color: .green, symbolName: "leaf"),
            Subject(name: "Sport", shortName: "Sp", color: .orange, symbolName: "figure.run"),
        ]
        for subject in subjects { model.upsert(subject) }
        let ids = model.subjects.map(\.id)
        // (weekday, start, subject index); 45-minute lessons.
        let plan: [(Int, Int, Int)] = [
            (0, 8 * 60, 0), (0, 8 * 60 + 50, 1), (0, 9 * 60 + 50, 2), (0, 10 * 60 + 40, 3),
            (1, 8 * 60, 1), (1, 8 * 60 + 50, 0), (1, 9 * 60 + 50, 4),
            (2, 8 * 60, 2), (2, 8 * 60 + 50, 3), (2, 9 * 60 + 50, 0),
            (3, 8 * 60, 0), (3, 8 * 60 + 50, 2), (3, 9 * 60 + 50, 1),
            (4, 8 * 60, 3), (4, 8 * 60 + 50, 4), (4, 9 * 60 + 50, 1),
        ]
        for (weekday, start, subject) in plan where subject < ids.count {
            _ = model.save(Lesson(subjectID: ids[subject], weekday: weekday, startMinute: start, endMinute: start + 45, room: "A\(10 + subject)"))
        }
        // Meldungen over the last three weeks (none today, so the first tap is visible).
        let today = calendar.startOfDay(for: now)
        for dayOffset in 1...20 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today),
                  !calendar.isDateInWeekend(day) else { continue }
            for i in 0..<(dayOffset % 3 + 1) {
                let at = day.addingTimeInterval(TimeInterval((8 * 60 + 10 + i * 50) * 60))
                model.recordParticipation(subjectID: ids[(dayOffset + i) % ids.count], at: at)
            }
        }
        model.setWeeklyGoal(12)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        model.upsert(SchoolTask(title: "Aufgaben S. 42, Nr. 3–5", subjectID: ids[0], dueDate: tomorrow, priority: .high))
        model.upsert(SchoolTask(title: "Gedichtanalyse fertig schreiben", subjectID: ids[1], dueDate: nextWeek))
        model.upsert(SchoolTask(title: "Vokabeln Unit 3", kind: .homework, subjectID: ids[2], dueDate: today, recurrence: .weekly))
        model.upsert(SchoolTask(title: "Sportsachen einpacken", kind: .todo))
    }
}

/// Two school weeks as WebUntis would send them (JSON-RPC `getTimetable` and the
/// extras), run through the real import: parallel Religion/Ethik, Physik/Chemie
/// in A/B weeks, an Entfall, a Vertretung, a room change, an exam, homework,
/// news and absences. Test data for the simulator, never shown to students.
private enum UntisSampleData {
    static func seed(_ model: AppModel, now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let monday = calendar.date(byAdding: .day, value: -calendar.mondayIndex(of: today), to: today) ?? today
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday) ?? monday }
        func ymd(_ date: Date) -> Int {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
        }
        func ffi(_ date: Date) -> FfiDate { FfiDate(date, calendar: calendar) }
        let bells = [(800, 845), (850, 935), (950, 1035), (1040, 1125)]
        let subjects: [String: (String, String, String)] = [   // short: (long, teacher, room)
            "M": ("Mathematik", "WEB", "A10"), "D": ("Deutsch", "SCH", "A11"), "E": ("Englisch", "MÜL", "A12"),
            "BIO": ("Biologie", "FIS", "N1"), "SP": ("Sport", "HOF", "Halle"), "GE": ("Geschichte", "KRA", "A14"),
            "R": ("Religion", "KLE", "B1"), "ETH": ("Ethik", "BRA", "B2"), "PH": ("Physik", "NEU", "N2"), "CH": ("Chemie", "ROT", "N3"),
        ]
        // Weekday → periods (bell index, subject); "PH/CH" alternates by week.
        let week: [[(Int, String)]] = [
            [(0, "M"), (1, "D"), (2, "R"), (2, "ETH"), (3, "E")],
            [(0, "BIO"), (1, "M"), (2, "SP"), (3, "SP")],
            [(0, "E"), (1, "PH/CH"), (2, "D")],
            [(0, "D"), (1, "M"), (2, "GE")],
            [(0, "E"), (1, "BIO"), (2, "M")],
        ]
        var periods: [[String: Any]] = []
        var id = 1000
        func add(_ date: Date, _ bell: Int, _ short: String, code: String? = nil, room: String? = nil,
                 orgRoom: String? = nil, teacher: String? = nil, exam: Bool = false, text: String? = nil) {
            guard let s = subjects[short] else { return }
            id += 1
            var ro: [String: Any] = ["name": room ?? s.2, "longname": room ?? s.2]
            if let orgRoom { ro["orgname"] = orgRoom }
            var p: [String: Any] = [
                "id": id, "date": ymd(date), "startTime": bells[bell].0, "endTime": bells[bell].1,
                "su": [["name": short, "longname": s.0]], "ro": [ro], "te": [["name": teacher ?? s.1, "longname": teacher ?? s.1]],
            ]
            if let code { p["code"] = code }
            if exam { p["lstype"] = "ex" }
            if let text { p["lstext"] = text }
            periods.append(p)
        }
        for w in 0..<2 {
            for (weekday, list) in week.enumerated() {
                let date = day(w * 7 + weekday)
                for (bell, raw) in list {
                    let short = raw == "PH/CH" ? (w == 0 ? "PH" : "CH") : raw
                    switch (w, weekday, bell, short) {
                    case (0, 1, 2, "SP"):   // Tuesday: Sport is cancelled.
                        add(date, bell, short, code: "cancelled")
                    case (0, 2, 2, "D"):    // Wednesday: Geschichte replaces Deutsch.
                        add(date, bell, short, code: "cancelled")
                        add(date, bell, "GE", code: "irregular", text: "Vertretung")
                    case (0, 3, 1, "M"):    // Thursday: Mathe in another room.
                        add(date, bell, short, room: "B3", orgRoom: "A10")
                    case (0, 4, 2, "M"):    // Friday: Klassenarbeit.
                        add(date, bell, short, exam: true, text: "Klassenarbeit Nr. 2")
                    case (0, 0, 3, "E"):
                        add(date, bell, short, text: "Bitte Workbook mitbringen")
                    default:
                        add(date, bell, short)
                    }
                }
            }
        }
        let envelope: [String: Any] = ["jsonrpc": "2.0", "id": "1", "result": periods]
        guard let json = try? JSONSerialization.data(withJSONObject: envelope),
              let body = String(data: json, encoding: .utf8) else { return }
        let link = UntisLink(server: "beispiel.webuntis.com", loginName: "beispielschule",
                             schoolName: "Beispielschule (Testdaten)", user: "testschueler", lastSync: now)
        model.importUntisSample(
            link: link, body: body,
            bells: bells.enumerated().map { FfiTimeUnit(name: "\($0.offset + 1)", startMinute: UInt16($0.element.0 / 100 * 60 + $0.element.0 % 100), endMinute: UInt16($0.element.1 / 100 * 60 + $0.element.1 % 100)) },
            holidays: [FfiUntisHoliday(name: "Weihnachtsferien", firstDay: ffi(day(65)), lastDay: ffi(day(79)))],
            absences: [
                FfiUntisAbsence(id: 1, firstDay: ffi(day(-12)), lastDay: ffi(day(-12)), startMinute: 480, endMinute: 685, reason: "Krankheit", text: "", excused: true),
                FfiUntisAbsence(id: 2, firstDay: ffi(day(-5)), lastDay: ffi(day(-5)), startMinute: 480, endMinute: 525, reason: "Verspätung", text: "", excused: false),
            ],
            exams: [
                FfiUntisExam(id: 1, date: ffi(day(4)), startMinute: 590, endMinute: 635, subject: "M", name: "Klassenarbeit Nr. 2", examType: "Klassenarbeit", teachers: ["WEB"], rooms: ["A10"], text: "Kapitel 3 und 4"),
                FfiUntisExam(id: 2, date: ffi(day(16)), startMinute: 480, endMinute: 525, subject: "E", name: "Vokabeltest", examType: "Test", teachers: ["MÜL"], rooms: ["A12"], text: ""),
            ],
            homework: [
                FfiUntisHomework(id: 1, subject: "M", given: ffi(day(-3)), due: ffi(day(1)), text: "Buch S. 42, Nr. 3–5", remark: "", completed: false),
                FfiUntisHomework(id: 2, subject: "E", given: ffi(day(-7)), due: ffi(day(-3)), text: "Text S. 18 lesen", remark: "", completed: true),
                FfiUntisHomework(id: 3, subject: "D", given: ffi(day(0)), due: ffi(day(9)), text: "Gedichtanalyse", remark: "mind. eine Seite", completed: false),
            ],
            news: [FfiUntisNews(id: 1, subject: "Lehrerkonferenz", text: "Am Freitag endet der Unterricht nach der 4. Stunde.")]
        )
        // Some Meldungen from last week on the imported lessons.
        if let math = model.subjects.first(where: { $0.untisKey == "M" }), let german = model.subjects.first(where: { $0.untisKey == "D" }) {
            for offset in [-7, -6, -4, -3] {
                model.recordParticipation(subjectID: math.id, at: day(offset).addingTimeInterval(8 * 3600 + 600))
                model.recordParticipation(subjectID: german.id, at: day(offset).addingTimeInterval(9 * 3600))
            }
        }
        model.setWeeklyGoal(10)
    }
}
#endif
