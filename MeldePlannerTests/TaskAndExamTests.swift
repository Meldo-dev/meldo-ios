import Foundation
import Testing
import UIKit
@testable import MeldePlanner

@Suite("Tasks, exams and data migration")
struct TaskAndExamTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    /// Wednesday 2026-10-21 at the given local time.
    func wednesday(_ hour: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour))!
    }

    func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d))!
    }

    func makeModel(store: LocalStore? = nil) -> AppModel {
        AppModel(store: store, calendar: calendar, now: { self.wednesday() })
    }

    @Test func completingRecurringTaskCreatesNextInstance() throws {
        let model = makeModel()
        let vocab = SchoolTask(title: "Vokabeln", dueDate: day(21), recurrence: .weekly)
        model.upsert(vocab)
        model.toggleDone(vocab.id)
        #expect(model.task(vocab.id)?.isDone == true)
        let next = try #require(model.tasks.first { $0.id != vocab.id })
        #expect(next.title == "Vokabeln")
        #expect(next.dueDate == day(28))
        #expect(!next.isDone)
    }

    @Test func sectionsComeFromRustGrouping() {
        let model = makeModel()
        model.upsert(SchoolTask(title: "Überfällig", dueDate: day(20)))
        model.upsert(SchoolTask(title: "Heute", dueDate: day(21)))
        model.upsert(SchoolTask(title: "Notiz", kind: .todo))
        let groups = model.taskSections(today: wednesday()).map(\.group)
        #expect(groups == [.overdue, .today, .noDate])
        #expect(model.upcomingHomework(today: wednesday()).map(\.title) == ["Überfällig", "Heute"])
    }

    @Test func homeworkStreakCountsOnTimeDays() {
        let model = makeModel()
        let monday = SchoolTask(title: "Mo", dueDate: day(19))
        let tuesday = SchoolTask(title: "Di", dueDate: day(20))
        model.upsert(monday)
        model.upsert(tuesday)
        #expect(model.homeworkStreak(asOf: wednesday()) == 0)
        // Checked off "now" (Wednesday): late for both, so still no streak.
        model.toggleDone(monday.id)
        #expect(model.homeworkStreak(asOf: wednesday()) == 0)
    }

    @Test func homeworkDefaultsToNextLessonOfSubject() {
        let model = makeModel()
        let math = Subject(name: "Mathe")
        model.upsert(math)
        // Friday lesson.
        _ = model.save(Lesson(subjectID: math.id, weekday: 4, startMinute: 480, endMinute: 525))
        #expect(model.nextLessonDay(for: math.id, after: wednesday()) == day(23))
    }

    @Test func versionOneFilesStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "melde-v1-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // Shape written by the first sideloaded build: no tasks, no exams.
        let v1 = """
        {"schemaVersion":1,"subjects":[{"id":"6F1A2B3C-0000-0000-0000-000000000001","name":"Mathe","shortName":"","color":"blue","symbolName":"function","teacher":"","updatedAt":"2026-10-20T08:00:00Z"}],
         "lessons":[],"holidays":[],"participation":[{"id":"6F1A2B3C-0000-0000-0000-0000000000AA","subjectID":"6F1A2B3C-0000-0000-0000-000000000001","recordedAt":"2026-10-20T08:10:00Z"}],
         "preferences":{"language":"de","theme":"system","weeklyGoal":12}}
        """
        try Data(v1.utf8).write(to: url)
        let model = makeModel(store: LocalStore(url: url))
        #expect(model.storageProblem == nil)
        #expect(model.subjects.map(\.name) == ["Mathe"])
        #expect(model.data.participation.count == 1)
        #expect(model.preferences.weeklyGoal == 12)
        #expect(model.tasks.isEmpty)
        #expect(model.data.schemaVersion == AppData.currentSchemaVersion)
    }

    @Test func oldDataCopiesAreRemoved() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appending(path: "melde-leftovers-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let names = ["data-before-app-group.json", "data-unreadable-1000000000.json",
                     "data-unreadable-\(Int(now.timeIntervalSince1970) - 3600).json", "data.json"]
        for name in names { try Data("{}".utf8).write(to: folder.appending(path: name)) }
        LocalStore.removeLeftovers(in: [folder], now: now)
        let left = try fm.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
        // The migration copy and an old unreadable copy go; a recent one and the data stay.
        #expect(left == ["data-unreadable-\(Int(now.timeIntervalSince1970) - 3600).json", "data.json"])
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
