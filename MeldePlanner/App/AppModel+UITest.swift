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
            let model = UITestLaunch(arguments: args).makeModel()
            MeldoFeatures.app.install(in: model)
            return model
        }
        #endif
        let model = AppModel(store: try? LocalStore.standard())
        MeldoFeatures.app.install(in: model)
        return model
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
            MeldoFeatures.app.feature("untis")?.seedSample?(model, fixed)
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
#endif
