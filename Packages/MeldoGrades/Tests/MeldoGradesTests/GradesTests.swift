import Foundation
import MeldoKit
import MeldoState
import Testing
@testable import MeldoGrades

@Suite("Grades")
struct GradesTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    /// Monday 2026-10-19 at the given local time.
    func monday(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour, minute: minute))!
    }

    func makeModel(at date: Date) -> AppModel {
        AppModel(store: nil, calendar: calendar, now: { date })
    }

    @Test func subjectGradeReadsLikeAReportCard() {
        let model = makeModel(at: monday(8, 0))
        let math = Subject(name: "Mathe")
        model.upsert(math)
        #expect(model.subjectGradeText(for: math.id) == nil)
        for value in [2.0, 2.5] {
            model.saveGrade(GradeEntry(subjectID: math.id, value: value, written: true, date: monday(8, 0)))
        }
        // Exact Schnitt 2,25; the subject's grade is the nearest tendency (2− = 2,33 with step 0,33).
        #expect(model.gradeSummary(for: math.id)?.exact == 2.25)
        #expect(model.subjectGradeText(for: math.id) == "2\u{2212}")
        #expect(model.singleGradeText(1.67) == "2+")
        #expect(model.singleGradeText(1.0) == "1")

        // Oberstufe: 10 and 11 points average 10,5, which rounds to 11 in the student's favour.
        let points = makeModel(at: monday(8, 0))
        points.setGradeScale(.points)
        let bio = Subject(name: "Bio")
        points.upsert(bio)
        for value in [10.0, 11.0] {
            points.saveGrade(GradeEntry(subjectID: bio.id, value: value, written: true, date: monday(8, 0)))
        }
        #expect(points.subjectGradeText(for: bio.id) == "11 P.")
    }
}
