import Foundation
import MeldeCore
import Testing
@testable import MeldePlanner

@Suite("WebUntis import merge")
struct UntisImportTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d))!
    }

    /// Two weeks from Monday 2026-10-19: Mathe weekly at 08:00 (cancelled on the 26th),
    /// Physik / Chemie alternating at 10:00.
    let body = """
    {"jsonrpc":"2.0","id":"meldo","result":[
      {"id":1,"date":20261019,"startTime":800,"endTime":845,"su":[{"id":2,"name":"M","longname":"Mathematik"}],"ro":[{"id":1,"name":"A1"}]},
      {"id":2,"date":20261026,"startTime":800,"endTime":845,"su":[{"id":2,"name":"M","longname":"Mathematik"}],"ro":[{"id":1,"name":"A1"}],"code":"cancelled"},
      {"id":3,"date":20261019,"startTime":1000,"endTime":1045,"su":[{"id":3,"name":"PH","longname":"Physik"}],"ro":[]},
      {"id":4,"date":20261026,"startTime":1000,"endTime":1045,"su":[{"id":4,"name":"CH","longname":"Chemie"}],"ro":[]}
    ]}
    """

    @Test func mergesIntoExistingData() throws {
        let model = AppModel(store: nil, calendar: calendar, now: { self.day(21) })
        // The student already has Mathematik with a Monday 08:00 lesson and a Meldung in it.
        let math = Subject(name: "Mathematik", color: .red)
        model.upsert(math)
        let lesson = Lesson(subjectID: math.id, weekday: 0, startMinute: 480, endMinute: 525)
        #expect(model.save(lesson).isEmpty)

        let monday = FfiDate(year: 2026, month: 10, day: 19)
        let schedule = try untisDeriveSchedule(timetableBody: body, weekAStart: monday)
        let link = UntisLink(server: "nessa.webuntis.com", loginName: "gym", schoolName: "Gymnasium", user: "max")
        let summary = model.applyUntis(schedule, weekAStart: day(19), link: link)

        #expect(summary.newSubjects == 2) // Physik, Chemie; Mathematik is reused.
        #expect(model.subjects.count == 3)
        #expect(model.subjects.first { $0.id == math.id }?.untisKey == "M")
        #expect(model.subjects.first { $0.id == math.id }?.color == .red) // keeps the student's color
        // The existing lesson keeps its id (so Meldungen stay linked) and is now from Untis.
        #expect(model.lessons.first { $0.id == lesson.id }?.fromUntis == true)
        #expect(model.lessons.count == 3)
        // Alternating lessons switch on A/B weeks with the imported week as A.
        #expect(model.preferences.weekAReference == day(19))
        #expect(model.lessons.contains { $0.parity == .a } && model.lessons.contains { $0.parity == .b })
        // The cancellation on the 26th is applied by the Rust timetable.
        let mathOn26 = model.occurrences(on: day(26)).first { $0.lessonId == lesson.id.uuidString }
        #expect(mathOn26?.cancelled == true)
        #expect(model.untisLink?.user == "max")
    }

    @Test func reimportReplacesUntisChangesAndDisconnectKeepsLessons() throws {
        let model = AppModel(store: nil, calendar: calendar, now: { self.day(21) })
        let monday = FfiDate(year: 2026, month: 10, day: 19)
        let schedule = try untisDeriveSchedule(timetableBody: body, weekAStart: monday)
        let link = UntisLink(server: "s", loginName: "l", schoolName: "n", user: "u")
        _ = model.applyUntis(schedule, weekAStart: day(19), link: link)
        _ = model.applyUntis(schedule, weekAStart: day(19), link: link)
        #expect(model.data.changes.count == 1)
        #expect(model.subjects.count == 3)

        model.disconnectUntis()
        #expect(model.untisLink == nil)
        #expect(model.data.changes.isEmpty)
        #expect(model.lessons.count == 3)
        #expect(model.lessons.allSatisfy { $0.fromUntis == nil })
    }

    @Test func renewalLinkStaysOnTheSchoolServer() {
        let ok = UntisSilentLogin.ssoURL("/WebUntis/oauth2/authorization/office365", server: "gso.webuntis.com")
        #expect(ok?.url?.absoluteString == "https://gso.webuntis.com/WebUntis/oauth2/authorization/office365")
        for bad in ["//evil.com/WebUntis/x", "/WebUntis//evil.com", "https://evil.com/WebUntis/x", "/other/path", "/WebUntis/\\evil.com"] {
            #expect(UntisSilentLogin.ssoURL(bad, server: "gso.webuntis.com") == nil, "\(bad)")
        }
    }

    @Test func guessesSymbols() {
        #expect(SubjectSymbols.guess(for: "Mathematik") == "function")
        #expect(SubjectSymbols.guess(for: "Evangelische Religion") == "hands.and.sparkles")
        #expect(SubjectSymbols.guess(for: "Robotik-AG") == "book.closed")
    }
}
