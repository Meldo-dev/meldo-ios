import Foundation
import Testing
@testable import MeldePlanner

@Suite("Shared store, engine and check-ins")
struct SharedStoreTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    func monday(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour, minute: minute))!
    }

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "melde-shared-\(UUID().uuidString).json")
    }

    @Test func widgetWriteIsNotLostWhenAppSaves() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let app = AppModel(store: LocalStore(url: url), calendar: calendar, now: { self.monday(8, 10) })
        app.upsert(Subject(name: "Mathe"))

        // Another process (widget / Control Center) logs a Meldung on the same file.
        let widget = LocalStore(url: url, isShared: true)
        try widget.update { $0.participation.append(ParticipationEntry(subjectID: nil, recordedAt: self.monday(8, 11))) }

        // The app, still holding stale in-memory data, saves an unrelated change.
        app.setWeeklyGoal(10)
        #expect(app.data.participation.count == 1)
        let onDisk = try LocalStore(url: url).load()
        #expect(onDisk.participation.count == 1)
        #expect(onDisk.preferences.weeklyGoal == 10)
    }

    @Test func engineRecordsForCurrentLessonOnly() {
        var data = AppData()
        let math = Subject(name: "Mathe")
        data.subjects = [math]
        data.lessons = [Lesson(subjectID: math.id, weekday: 0, startMinute: 480, endMinute: 525)]
        let entry = MeldeEngine.recordForLesson(in: &data, at: monday(8, 20), calendar: calendar)
        #expect(entry?.subjectID == math.id)
        #expect(MeldeEngine.recordForLesson(in: &data, at: monday(12, 0), calendar: calendar) == nil)
        #expect(data.participation.count == 1)
    }

    @Test func checkInAnswerRecordsEntries() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalStore(url: url)
        let lessonID = UUID()
        let subject = Subject(name: "Mathe")
        let subjectID = subject.id
        var initial = AppData()
        initial.subjects = [subject]
        try store.save(initial)
        let changed = LessonCheckIns.handle(
            actionIdentifier: "CHECKIN_TWICE",
            userInfo: [
                "lessonID": lessonID.uuidString,
                "subjectID": subjectID.uuidString,
                "recordedAt": monday(8, 43).timeIntervalSince1970,
            ],
            store: store
        )
        #expect(changed)
        let data = try store.load()
        #expect(data.participation.count == 2)
        #expect(data.participation.allSatisfy { $0.lessonID == lessonID && $0.subjectID == subjectID })

        // "Diesmal nicht" records nothing.
        #expect(!LessonCheckIns.handle(actionIdentifier: "CHECKIN_SKIP", userInfo: [:], store: store))
        #expect(try store.load().participation.count == 2)

        // An old notification answered again doesn't count the lesson twice.
        let again = ["lessonID": lessonID.uuidString, "subjectID": subjectID.uuidString,
                     "recordedAt": monday(8, 43).timeIntervalSince1970] as [AnyHashable: Any]
        #expect(!LessonCheckIns.handle(actionIdentifier: "CHECKIN_ONCE", userInfo: again, store: store))
        #expect(try store.load().participation.count == 2)
    }

    @Test func checkInForADeletedSubjectKeepsNoStaleID() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalStore(url: url)
        let info = ["lessonID": UUID().uuidString, "subjectID": UUID().uuidString,
                    "recordedAt": monday(8, 43).timeIntervalSince1970] as [AnyHashable: Any]
        #expect(LessonCheckIns.handle(actionIdentifier: "CHECKIN_ONCE", userInfo: info, store: store))
        #expect(try store.load().participation.first?.subjectID == nil)
    }

    @Test func preferencesFromOlderFilesGetDefaults() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"schemaVersion":2,"preferences":{"language":"tr"}}"#.utf8).write(to: url)
        let data = try LocalStore(url: url).load()
        #expect(data.preferences.language == .german, "Turkish was dropped: German instead")
        #expect(data.preferences.askAfterLesson == false)
        #expect(data.preferences.liveActivities == true)
    }
}
