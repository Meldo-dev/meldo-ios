import Foundation
import MeldeCore
import MeldoKit
import MeldoState

#if DEBUG
/// Two school weeks as WebUntis would send them (JSON-RPC `getTimetable` and the
/// extras), run through the real import: parallel Religion/Ethik, Physik/Chemie
/// in A/B weeks, an Entfall, a Vertretung, a room change, an exam, homework,
/// news and absences. Test data for the simulator, never shown to students.
enum UntisSampleData {
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
