import Foundation
import Testing
@testable import MeldePlanner

@Suite("AppModel")
struct AppModelTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    /// Monday 2026-10-19 at the given local time.
    func monday(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour, minute: minute))!
    }

    func makeModel(at date: Date, store: LocalStore? = nil) -> AppModel {
        AppModel(store: store, calendar: calendar, now: { date })
    }

    func addMathMonday(_ model: AppModel) -> (Subject, Lesson) {
        let math = Subject(name: "Mathe")
        model.upsert(math)
        let lesson = Lesson(subjectID: math.id, weekday: 0, startMinute: 8 * 60, endMinute: 8 * 60 + 45)
        #expect(model.save(lesson).isEmpty)
        return (math, lesson)
    }

    @Test func oneTapRecordsForCurrentLesson() {
        let model = makeModel(at: monday(8, 10))
        let (math, lesson) = addMathMonday(model)
        guard case .recorded(let entry) = model.recordParticipation() else {
            Issue.record("expected an automatic assignment")
            return
        }
        #expect(entry.subjectID == math.id)
        #expect(entry.lessonID == lesson.id)
        #expect(model.weekSummary(containing: monday(12, 0))?.total == 1)
    }

    @Test func graceWindowAfterTheBell() {
        let model = makeModel(at: monday(8, 48))
        _ = addMathMonday(model)
        #expect(model.recordParticipation() != .needsSubject)
    }

    @Test func cancelledLessonIsNotBookedAutomatically() {
        let model = makeModel(at: monday(8, 10))
        let (_, lesson) = addMathMonday(model)
        model.mutate { $0.changes.append(TimetableChangeRecord(lessonID: lesson.id, date: calendar.startOfDay(for: monday(8, 10)), kind: .cancelled)) }
        #expect(model.recordParticipation() == .needsSubject)
        #expect(model.data.participation.isEmpty)
    }

    @Test func parallelCoursesAskOnceThenBookTheChosenOne() {
        let model = makeModel(at: monday(8, 10))
        let religion = Subject(name: "Religion")
        let ethics = Subject(name: "Ethik")
        model.upsert(religion)
        model.upsert(ethics)
        // Parallel courses as WebUntis imports them (the editor refuses overlaps).
        model.mutate { data in
            data.lessons.append(Lesson(subjectID: religion.id, weekday: 0, startMinute: 8 * 60, endMinute: 8 * 60 + 45))
            data.lessons.append(Lesson(subjectID: ethics.id, weekday: 0, startMinute: 8 * 60, endMinute: 8 * 60 + 45))
        }
        guard case .needsCourse(let options) = model.recordParticipation() else {
            Issue.record("expected the course question")
            return
        }
        #expect(Set(options) == [religion.id, ethics.id])
        #expect(model.data.participation.isEmpty)
        guard case .recorded(let first) = model.recordParticipation(choosingCourse: ethics.id, among: options) else {
            Issue.record("expected a Meldung for the chosen course")
            return
        }
        #expect(first.subjectID == ethics.id)
        // Next time it's one tap again.
        guard case .recorded(let second) = model.recordParticipation() else {
            Issue.record("expected an automatic assignment after choosing")
            return
        }
        #expect(second.subjectID == ethics.id)
    }

    @Test func outsideLessonsAsksForSubject() {
        let model = makeModel(at: monday(13, 0))
        let (math, _) = addMathMonday(model)
        #expect(model.recordParticipation() == .needsSubject)
        let entry = model.recordParticipation(subjectID: math.id)
        #expect(model.entries(on: monday(13, 0)).map(\.id) == [entry.id])
    }

    @Test func overlappingLessonIsRejectedByRustCore() {
        let model = makeModel(at: monday(7, 0))
        let (math, _) = addMathMonday(model)
        let clash = Lesson(subjectID: math.id, weekday: 0, startMinute: 8 * 60 + 30, endMinute: 9 * 60 + 15)
        #expect(!model.save(clash).isEmpty)
        #expect(model.lessons.count == 1)
    }

    @Test func deletingSubjectKeepsMeldungenWithoutSubject() {
        let model = makeModel(at: monday(8, 10))
        let (math, _) = addMathMonday(model)
        _ = model.recordParticipation()
        model.deleteSubject(math.id)
        #expect(model.lessons.isEmpty)
        #expect(model.data.participation.count == 1)
        #expect(model.data.participation[0].subjectID == nil)
        #expect(model.data.participation[0].lessonID == nil)
    }

    @Test func persistsAcrossLaunches() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "melde-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalStore(url: url)

        let first = makeModel(at: monday(8, 10), store: store)
        _ = addMathMonday(first)
        _ = first.recordParticipation()
        first.setWeeklyGoal(12)

        let second = makeModel(at: monday(9, 0), store: store)
        #expect(second.subjects.map(\.name) == ["Mathe"])
        #expect(second.data.participation.count == 1)
        #expect(second.preferences.weeklyGoal == 12)
    }

    @Test func corruptFileIsBackedUpNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "melde-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "data.json")
        try Data("not json".utf8).write(to: url)

        let model = makeModel(at: monday(8, 0), store: LocalStore(url: url))
        #expect(model.storageProblem != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(files.contains { $0.hasPrefix("data-unreadable-") })
    }

    @Test func weekParityFollowsReference() {
        let model = makeModel(at: monday(8, 0))
        model.setCurrentWeekIsA(true)
        #expect(model.isWeekA(monday(8, 0)))
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: monday(8, 0))!
        #expect(!model.isWeekA(nextWeek))
        model.setCurrentWeekIsA(false)
        #expect(!model.isWeekA(monday(8, 0)))
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

    @Test(arguments: [
        (false, false, false, true),
        (true, false, false, false),
        (false, true, false, false),
        (false, false, true, false),
    ])
    func onboardingOnlyForNewStudents(seen: Bool, hasSubjects: Bool, hasUntis: Bool, shows: Bool) {
        #expect(Onboarding.shouldShow(seen: seen, hasSubjects: hasSubjects, hasUntis: hasUntis) == shows)
    }

    @Test func onboardingIsShownOnceAndRemembered() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "melde-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = makeModel(at: monday(8, 0), store: LocalStore(url: url))
        #expect(first.showingOnboarding)
        first.finishOnboarding()
        #expect(!first.showingOnboarding)

        let second = makeModel(at: monday(9, 0), store: LocalStore(url: url))
        #expect(!second.showingOnboarding)
        // Reopening from Mehr shows it without resetting the remembered choice.
        second.showOnboardingAgain()
        #expect(second.showingOnboarding)
        #expect(second.preferences.onboardingSeen)
    }

    @Test func existingStudentsWhoUpdateNeverSeeTheTour() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "melde-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // A file from before the tour existed: subjects, no "onboardingSeen".
        let old = folder.appending(path: "old.json")
        try Data(#"{"schemaVersion":2,"subjects":[{"id":"6F1A2B3C-0000-0000-0000-000000000001","name":"Mathe","shortName":"","color":"blue","symbolName":"function","teacher":"","updatedAt":"2026-10-20T08:00:00Z"}],"preferences":{"language":"de"}}"#.utf8).write(to: old)
        #expect(!makeModel(at: monday(8, 0), store: LocalStore(url: old)).showingOnboarding)

        // An unreadable file looks empty, but its owner isn't new.
        let broken = folder.appending(path: "broken.json")
        try Data("not json".utf8).write(to: broken)
        let model = makeModel(at: monday(8, 0), store: LocalStore(url: broken))
        #expect(model.storageProblem != nil)
        #expect(!model.showingOnboarding)
    }
}
