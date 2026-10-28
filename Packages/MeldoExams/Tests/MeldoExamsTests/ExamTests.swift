import Foundation
import MeldoKit
import MeldoState
import Testing
import UIKit
@testable import MeldoExams

@Suite("Exams")
struct ExamTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d))!
    }

    func makeModel() -> AppModel {
        AppModel(store: nil, calendar: calendar, now: { self.day(21) })
    }

    @Test func examPDFsAreStoredAndRemoved() throws {
        let model = makeModel()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 280)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 280))
        }
        let pdf = try #require(ExamFiles.pdf(from: [image, image]))
        let exam = try model.addExam(pdf: pdf, title: "1. Klassenarbeit", subjectID: nil, date: day(21), grade: "2-", notes: "")
        #expect(exam.pageCount == 2)
        let url = try #require(model.fileURL(for: exam))
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        model.deleteExam(exam.id)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(model.exams.isEmpty)
    }
}
