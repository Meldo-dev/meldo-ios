import UIKit
import XCTest

/// Uses Meldo like a student would and saves a screenshot of every screen.
/// Runs on iPhone and iPad simulators; screenshots are exported from the test
/// results and reviewed by hand. Steps that cannot find their element record a
/// failure but the walk continues, so one problem doesn't hide the rest.
final class MeldoUITests: XCTestCase {
    /// Monday, 08:10: the first lesson (Mathematik 08:00–08:45) is running.
    private let mondayInLesson = "2026-10-19T08:10"

    private var device: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    override func setUp() {
        continueAfterFailure = true
    }

    /// Monday, 13:00: school is over, so Melden asks for the subject.
    private let mondayAfterSchool = "2026-10-19T13:00"

    private func launch(seed: Bool, language: String = "de", theme: String = "system",
                        now: String? = nil, landscape: Bool = false, onboarding: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        // Store shots on a device whose iOS is newer than Xcode: XCUITest can't launch the app
        // there, so the host starts it with these arguments (devicectl) and the test attaches.
        if storeLanguage != nil {
            // xcodebuild installs the app when the test starts; the host launches it after that.
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 120), "start Meldo with devicectl")
            app.activate()
            return app
        }
        app.launchArguments = ["-uitest", "-uitest-now", now ?? mondayInLesson, "-uitest-language", language, "-uitest-theme", theme]
        if seed { app.launchArguments.append("-uitest-seed") }
        if onboarding { app.launchArguments.append("-uitest-onboarding") }
        app.launch()
        return app
    }

    /// `TEST_RUNNER_MELDO_STORE_LANGUAGE=de|en` on the xcodebuild command line: attach mode (see `launch`).
    private var storeLanguage: String? { ProcessInfo.processInfo.environment["MELDO_STORE_LANGUAGE"] }

    /// Screenshot of the whole screen once animations have settled.
    /// `XCUIScreen` captures rotated screens correctly; `app.screenshot()` does not.
    /// `settle` is longer for store shots so a screen grabbed from the host (`simctl io screenshot`) is settled too.
    private func shot(_ app: XCUIApplication, _ name: String, settle: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(device)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps a tab in the iPhone tab bar or the iPad sidebar / top bar.
    @discardableResult
    private func tab(_ app: XCUIApplication, _ name: String) -> Bool {
        let inBar = app.tabBars.buttons[name]
        if inBar.waitForExistence(timeout: 3) { inBar.tap(); return true }
        let anywhere = app.buttons[name].firstMatch
        if anywhere.waitForExistence(timeout: 3) { anywhere.tap(); return true }
        let cell = app.cells.staticTexts[name].firstMatch
        if cell.waitForExistence(timeout: 2) { cell.tap(); return true }
        XCTFail("tab \(name) not found")
        return false
    }

    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 4) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("\(what) not found")
            return false
        }
        element.tap()
        return true
    }

    /// Goes back one level; the back button carries the previous screen's title.
    private func back(_ app: XCUIApplication, to title: String) {
        let named = app.navigationBars.buttons[title]
        if named.waitForExistence(timeout: 2) { named.tap(); return }
        let first = app.navigationBars.buttons.element(boundBy: 0)
        if first.exists { first.tap() } else { XCTFail("no back button to \(title)") }
    }

    /// Scrolling down minimizes the iPhone tab bar; scroll back so every tab is tappable.
    private func scrollToTop(_ app: XCUIApplication) {
        app.swipeDown()
        app.swipeDown()
    }

    // MARK: - Flows

    /// First launch: create a subject and a lesson by hand, then Melden.
    func test01_firstRunCreatesSubjectLessonAndMeldung() {
        let app = launch(seed: false)
        shot(app, "01-empty-start")
        tap(app.buttons["Erstes Fach anlegen"], "Erstes Fach anlegen")
        let name = app.textFields["Name, z. B. Mathematik"]
        if tap(name, "subject name field") { name.typeText("Mathematik") }
        shot(app, "02-subject-editor")
        tap(app.buttons["Sichern"], "Sichern (subject)")

        tab(app, "Stundenplan")
        shot(app, "03-timetable-empty")
        tap(app.buttons["Stunde hinzufügen"].firstMatch, "Stunde hinzufügen")
        shot(app, "04-lesson-editor")
        tap(app.buttons["Sichern"], "Sichern (lesson)")
        shot(app, "05-timetable-one-lesson")

        tap(app.buttons["Meldung erfassen"].firstMatch, "Melden button")
        // Undo is offered for four seconds only, so check it before the screenshot.
        XCTAssertTrue(app.buttons["Rückgängig"].waitForExistence(timeout: 3), "undo should appear after Melden")
        shot(app, "06-after-melden")
        tab(app, "Start")
        shot(app, "07-start-with-meldung")
    }

    /// Every tab and screen with realistic data.
    func test02_everyScreenWithSampleData() {
        let app = launch(seed: true)
        shot(app, "10-start")
        app.swipeUp()
        shot(app, "11-start-scrolled")
        scrollToTop(app)

        tab(app, "Stundenplan")
        shot(app, "12-timetable")
        _ = app.buttons["Stunde hinzufügen"].firstMatch.waitForExistence(timeout: 2)
        // The neighbouring weeks are loaded off-screen for the sideways scroll; take one on screen.
        let lessons = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Mathematik'"))
        _ = lessons.firstMatch.waitForExistence(timeout: 3)
        let firstLesson = lessons.allElementsBoundByIndex.first { $0.isHittable } ?? lessons.firstMatch
        if firstLesson.waitForExistence(timeout: 3) {
            firstLesson.tap()
            shot(app, "13-lesson-detail")
            if app.buttons["Hausaufgabe eintragen"].waitForExistence(timeout: 2) {
                app.buttons["Hausaufgabe eintragen"].tap()
                shot(app, "14-homework-from-lesson")
                tap(app.buttons["Abbrechen"], "Abbrechen")
            } else {
                app.tap()
            }
        }

        tab(app, "Aufgaben")
        shot(app, "15-tasks")
        let check = app.buttons["Als erledigt markieren"].firstMatch
        if tap(check, "task check circle") { shot(app, "16-task-checked") }
        tap(app.buttons["Aufgabe hinzufügen"].firstMatch, "Aufgabe hinzufügen")
        shot(app, "17-task-editor")
        tap(app.buttons["Abbrechen"], "Abbrechen (task)")

        if device == "iphone" {
            // iPhone: Noten has the tab, Dokumente lives under Mehr.
            tab(app, "Noten")
            shot(app, "18a-grades")
            tab(app, "Mehr")
            tap(app.buttons["Dokumente"].firstMatch, "Dokumente in Mehr")
        } else {
            tab(app, "Dokumente")
        }
        shot(app, "18-exams-empty")
        if device == "iphone" { back(app, to: "Mehr") }

        if device == "ipad" {
            tab(app, "Kalender")
            shot(app, "19-calendar")
            tab(app, "Statistik")
            shot(app, "20-statistics")
        }

        if device == "ipad" {
            // iPad has no Mehr tab: every destination sits in the sidebar.
            for (label, name) in [("Abwesenheiten", "21-absences"), ("Ferien", "21b-holidays"), ("WebUntis", "22-webuntis"),
                                  ("Microsoft Teams", "22b-teams"), ("Einstellungen", "23-settings"), ("Fächer", "25-subjects"),
                                  ("Über Meldo", "26-about")] {
                if tab(app, label) { shot(app, name) }
            }
            return
        }
        tab(app, "Mehr")
        shot(app, "21-more")
        if device == "iphone" {
            tap(app.buttons["Kalender"].firstMatch, "Kalender in Mehr")
            shot(app, "19-calendar")
            back(app, to: "Mehr")
            tap(app.buttons["Statistik"].firstMatch, "Statistik in Mehr")
            shot(app, "20-statistics")
            back(app, to: "Mehr")
        }
        for (label, name) in [("Abwesenheiten", "21-absences"), ("Microsoft Teams", "22b-teams"),
                              ("WebUntis", "22-webuntis"), ("Einstellungen", "23-settings"),
                              ("Status: Widgets, Mitteilungen", "24-status"), ("Fächer", "25-subjects"),
                              ("Über Meldo", "26-about")] {
            if tap(app.buttons[label].firstMatch, label) {
                shot(app, name)
                if name == "23-settings" {
                    app.swipeUp()
                    shot(app, "23b-settings-scrolled")
                    app.swipeUp()
                    shot(app, "23c-settings-bottom")
                }
                back(app, to: "Mehr")
            }
        }
    }

    func test03_meldenAndUndo() {
        let app = launch(seed: true)
        let melden = app.buttons["Meldung erfassen"].firstMatch
        tap(melden, "Melden")
        // Undo first: it disappears after four seconds, longer than a slow simulator's screenshot.
        tap(app.buttons["Rückgängig"], "Rückgängig")
        shot(app, "31-melden-undone")
    }

    func test04_darkMode() {
        let app = launch(seed: true, theme: "dark")
        shot(app, "40-dark-start")
        tab(app, "Stundenplan")
        shot(app, "41-dark-timetable")
        tab(app, "Aufgaben")
        shot(app, "42-dark-tasks")
    }

    func test05_english() {
        let en = launch(seed: true, language: "en")
        shot(en, "51-en-start")
        tab(en, "Tasks")
        shot(en, "52-en-tasks")
    }

    func test06_coloredTheme() {
        let app = launch(seed: true, theme: "purple")
        shot(app, "60-purple-start")
    }

    /// Outside a lesson Melden asks which subject the Meldung belongs to.
    func test07_meldenAfterSchoolAsksForSubject() {
        let app = launch(seed: true, now: mondayAfterSchool)
        shot(app, "70-after-school-start")
        tap(app.buttons["Meldung erfassen"].firstMatch, "Melden")
        shot(app, "71-subject-picker")
        if tap(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Biologie'")).firstMatch, "Biologie in picker") {
            shot(app, "72-after-picking-subject")
        }
    }

    /// Finds a real school through the public WebUntis school search and opens
    /// its login form. No credentials are entered.
    func test09_webUntisSchoolSearch() {
        let app = launch(seed: true)
        if device == "ipad" {
            tab(app, "WebUntis")
        } else {
            tab(app, "Mehr")
            tap(app.buttons["WebUntis"].firstMatch, "WebUntis")
        }
        shot(app, "90-webuntis-empty")
        // Too general: WebUntis refuses it (-6003) and Meldo must explain why.
        let field = app.textFields["untis-school-search"]
        if tap(field, "school search field") {
            field.typeText("Köln")
            _ = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Zu viele Schulen'")).firstMatch.waitForExistence(timeout: 15)
            shot(app, "91a-webuntis-too-many")
            field.typeText("-Pesch")
            let school = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Pesch'")).firstMatch
            if school.waitForExistence(timeout: 15) {
                shot(app, "91-webuntis-results")
                school.tap()
                shot(app, "92-webuntis-login")
                // Opens the school's real WebUntis page; nothing is typed there.
                if tap(app.buttons["Mit Microsoft 365 oder Schul-Login anmelden"], "school login button") {
                    RunLoop.current.run(until: Date().addingTimeInterval(6))
                    shot(app, "93-webuntis-school-login-page")
                    tap(app.buttons["Abbrechen"], "Abbrechen (school login)")
                }
            } else {
                shot(app, "91-webuntis-no-results")
                XCTFail("no school found for Köln-Pesch")
            }
        }
    }

    /// The iPad is mostly used sideways; the iPhone checks landscape too.
    func test08_landscape() {
        let app = launch(seed: true, landscape: true)
        shot(app, "80-landscape-start")
        tab(app, "Stundenplan")
        shot(app, "81-landscape-timetable")
        tab(app, "Aufgaben")
        shot(app, "82-landscape-tasks")
        if device == "ipad" {
            tab(app, "Dokumente")
            shot(app, "83-landscape-exams")
            tab(app, "Statistik")
            shot(app, "84-landscape-statistics")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// App Store captures in German and English, named "store-<language>-<n>-<area>":
    /// iPad landscape with the sidebar, iPhone portrait.
    func test20_storeShots() {
        if let language = storeLanguage {
            if device == "ipad" { storeShotsIPadLandscape(language) } else { storeShotsIPhone(language) }
            return
        }
        // The first launch after install can miss the launch arguments on a slow simulator; warm up once.
        launch(seed: true).terminate()
        for language in ["de", "en"] {
            if device == "ipad" { storeShotsIPadLandscape(language) } else { storeShotsIPhone(language) }
        }
    }

    /// Tab and button labels the store walk taps, per language.
    private func label(_ german: String, _ language: String) -> String {
        guard language == "en" else { return german }
        return ["Start": "Home", "Stundenplan": "Timetable", "Aufgaben": "Tasks", "Noten": "Grades", "Kalender": "Calendar",
                "Statistik": "Statistics", "Dokumente": "Documents", "Mehr": "More", "Fertig": "Done",
                "Als erledigt markieren": "Mark as done"][german] ?? german
    }

    /// Taps the Mathematik lesson that is on screen (the week pager keeps other weeks off-screen).
    private func tapVisibleLesson(_ app: XCUIApplication) -> Bool {
        let lessons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mathematik'"))
        _ = lessons.firstMatch.waitForExistence(timeout: 3)
        for _ in 0..<10 {
            // iPad: skip last week's lessons peeking out under the sidebar.
            let minX = device == "ipad" ? app.frame.width * 0.25 : 0
            if let lesson = lessons.allElementsBoundByIndex.first(where: { $0.isHittable && $0.frame.minX >= minX }) {
                lesson.tap()
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("no visible Mathematik lesson")
        return false
    }

    private func storeShotsIPadLandscape(_ language: String) {
        let l = { self.label($0, language) }
        let app = launch(seed: true, language: language, landscape: true)
        let sidebarItem = app.buttons[l("Kalender")].firstMatch
        // Kalender also "exists" behind the collapsed top bar's overflow chevron; only a hittable
        // item in the left third is the sidebar.
        let sidebarShown = sidebarItem.waitForExistence(timeout: 3) && sidebarItem.isHittable
            && sidebarItem.frame.minX < app.frame.width / 3
        if !sidebarShown {
            // Collapsed to the top bar: open the sidebar with its toggle.
            let toggle = app.buttons["ToggleSideBar"].firstMatch
            if toggle.waitForExistence(timeout: 3) {
                toggle.tap()
            } else {
                app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Seitenleiste' OR label CONTAINS[c] 'sidebar'")).firstMatch.tap()
            }
        }
        shot(app, "store-\(language)-1-start", settle: 5)
        tab(app, l("Stundenplan"))
        shot(app, "store-\(language)-2-timetable", settle: 5)
        if tapVisibleLesson(app) {
            shot(app, "store-\(language)-3-lesson", settle: 5)
            app.buttons[l("Fertig")].firstMatch.tap()
        }
        for (name, shotName) in [("Aufgaben", "4-tasks"), ("Noten", "5-grades"), ("Kalender", "6-calendar"),
                                 ("Statistik", "7-statistics"), ("Dokumente", "8-documents")] {
            tab(app, l(name))
            shot(app, "store-\(language)-\(shotName)", settle: 5)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func storeShotsIPhone(_ language: String) {
        let l = { self.label($0, language) }
        let app = launch(seed: true, language: language)
        // Foreground isn't enough: right after the launch the screenshot can still be the home screen.
        _ = app.buttons[l("Start")].firstMatch.waitForExistence(timeout: 20)
        shot(app, "store-\(language)-1-start", settle: 5)
        tab(app, l("Stundenplan"))
        shot(app, "store-\(language)-2-timetable", settle: 5)
        if tapVisibleLesson(app) {
            shot(app, "store-\(language)-3-lesson", settle: 5)
            app.buttons[l("Fertig")].firstMatch.tap()
        }
        tab(app, l("Aufgaben"))
        tap(app.buttons[l("Als erledigt markieren")].firstMatch, "task check circle")
        shot(app, "store-\(language)-4-tasks", settle: 5)
        for (name, shotName) in [("Kalender", "5-calendar"), ("Statistik", "6-statistics")] {
            tab(app, l("Mehr"))
            tap(app.buttons[l(name)].firstMatch, "\(name) in Mehr")
            shot(app, "store-\(language)-\(shotName)", settle: 5)
            back(app, to: l("Mehr"))
        }
    }

    /// Website captures of the lesson Live Activity and the after-lesson check-in in
    /// Notification Center, named "notif-<language>-<n>-<what>". Attach mode only: it
    /// needs a real iPhone, where the host starts Meldo in demo mode.
    func test21_notificationShots() throws {
        guard let language = storeLanguage, device == "iphone" else { throw XCTSkip("needs attach mode on an iPhone") }
        let en = language == "en"
        let app = launch(seed: true, language: language)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func capture(_ name: String, settle: TimeInterval = 2) {
            RunLoop.current.run(until: Date().addingTimeInterval(settle))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "notif-\(language)-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        // The system asks once per install; accept so the test notification can arrive.
        func allowIfAsked() {
            let allow = springboard.buttons.matching(NSPredicate(format: "label IN {'Allow', 'Erlauben'}")).firstMatch
            if allow.waitForExistence(timeout: 2) { allow.tap() }
        }

        tab(app, label("Mehr", language))
        // Status is at the end of Mehr; the list loads rows only once they scroll in.
        let status = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Status'")).firstMatch
        for _ in 0..<5 where !(status.exists && status.isHittable) { app.swipeUp() }
        tap(status, "Status in Mehr")
        tap(app.buttons[en ? "Show preview" : "Vorschau anzeigen"].firstMatch, "Live Activity preview")
        allowIfAsked()
        // German reads "Testmitteilung in 5 Sekunden", English "Test notification in 5 seconds".
        let test = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] '5 Sek' OR label CONTAINS[c] '5 sec'")).firstMatch
        tap(test, "test notification")
        allowIfAsked()
        capture("0-status", settle: 1)

        // Notification Center: swipe down from the top-left edge of the home screen.
        XCUIDevice.shared.press(.home)
        // Let the notification arrive and its banner leave, so it is listed in Notification Center.
        RunLoop.current.run(until: Date().addingTimeInterval(12))
        let body = en ? "Did you raise your hand?" : "Hast du dich gemeldet?"
        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", body)).firstMatch
        var found = false
        for _ in 0..<3 where !found {
            let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.003))
            top.press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.6)))
            found = notification.waitForExistence(timeout: 5)
            if !found { XCUIDevice.shared.press(.home); RunLoop.current.run(until: Date().addingTimeInterval(1)) }
        }
        // Without it the screen may show the home screen or other apps' notifications: no capture.
        guard found else { return XCTFail("check-in notification in Notification Center") }
        // A single notification can sit collapsed at the bottom ("1 Notification"), where a
        // long-press opens it instead; a short drag up lists it above the Live Activity's edge.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        capture("1-live", settle: 4)

        // Long-press shows the answer buttons. Don't tap them: an answer would reach the real store.
        if notification.exists {
            notification.press(forDuration: 1.2)
            XCTAssertTrue(springboard.buttons[en ? "Yes, once" : "Ja, einmal"].waitForExistence(timeout: 5), "answer buttons")
            capture("2-checkin")
            // Close the expanded notification by tapping above it, then clear it.
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            if notification.waitForExistence(timeout: 3) {
                notification.swipeLeft()
                let clear = springboard.buttons.matching(NSPredicate(format: "label IN {'Clear', 'Löschen', 'Entfernen'}")).firstMatch
                if clear.waitForExistence(timeout: 2) { clear.tap() }
            }
        }
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCUIDevice.shared.press(.home)
    }

    /// First run: the tour, a language switch that must not close it, every
    /// page, then "Fach selbst anlegen" ends on Start with Melden one tap away.
    func test10_onboardingToFirstSubject() {
        let app = launch(seed: false, onboarding: true)
        XCTAssertTrue(app.staticTexts["Willkommen bei Meldo"].waitForExistence(timeout: 5), "tour should open on first run")
        shot(app, "100-onboarding-welcome")

        // Switching the language re-renders the tour in place.
        if tap(app.buttons["English"].firstMatch, "English segment") {
            XCTAssertTrue(app.staticTexts["Welcome to Meldo"].waitForExistence(timeout: 4), "tour should stay open in English")
            shot(app, "101-onboarding-welcome-en")
            tap(app.buttons["Deutsch"].firstMatch, "Deutsch segment")
        }
        XCTAssertTrue(app.staticTexts["Willkommen bei Meldo"].waitForExistence(timeout: 4))

        tap(app.buttons["onboarding-next"], "Weiter (1)")
        XCTAssertTrue(app.staticTexts["Melden mit einem Tipp"].waitForExistence(timeout: 3))
        shot(app, "102-onboarding-melden")
        tap(app.buttons["onboarding-next"], "Weiter (2)")
        XCTAssertTrue(app.staticTexts["Alles für deinen Schultag"].waitForExistence(timeout: 3))
        shot(app, "103-onboarding-overview")
        tap(app.buttons["onboarding-next"], "Weiter (3)")
        XCTAssertTrue(app.staticTexts["Wie startest du?"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboarding-next"].exists, "the last page has its own choices")
        shot(app, "104-onboarding-setup")

        tap(app.buttons["onboarding-add-subject"], "Fach selbst anlegen")
        let name = app.textFields["Name, z. B. Mathematik"]
        if tap(name, "subject name field") { name.typeText("Mathematik") }
        tap(app.buttons["Sichern"], "Sichern (subject)")

        XCTAssertTrue(app.buttons["Meldung erfassen"].firstMatch.waitForExistence(timeout: 5), "Melden should be one tap away")
        XCTAssertFalse(app.staticTexts["Wie startest du?"].exists, "tour should be closed")
        shot(app, "105-onboarding-done")
    }

    /// Skipping lands on the empty Start; the tour can be opened again from Mehr.
    func test11_onboardingSkipAndReopen() {
        let app = launch(seed: false, onboarding: true)
        tap(app.buttons["onboarding-skip"], "Überspringen")
        XCTAssertTrue(app.buttons["Erstes Fach anlegen"].waitForExistence(timeout: 4), "skip should land on Start")
        XCTAssertFalse(app.staticTexts["Willkommen bei Meldo"].exists)
        shot(app, "110-onboarding-skipped")

        if device == "ipad" {
            tab(app, "Über Meldo")
            tap(app.buttons["Einführung ansehen"].firstMatch, "Einführung ansehen (Über Meldo)")
        } else {
            tab(app, "Mehr")
            tap(app.buttons["show-onboarding"], "Einführung ansehen")
        }
        XCTAssertTrue(app.staticTexts["Willkommen bei Meldo"].waitForExistence(timeout: 4), "tour should open again")
        shot(app, "111-onboarding-reopened")
        tap(app.buttons["onboarding-skip"], "Überspringen (again)")
        XCTAssertFalse(app.staticTexts["Willkommen bei Meldo"].waitForExistence(timeout: 2))
    }

    /// Tapping Stundenplan again while it's open brings back this week (Monday 19.10. is KW 43).
    func test12_timetableTabTapReturnsToToday() {
        let app = launch(seed: true)
        tab(app, "Stundenplan")
        tap(app.navigationBars.buttons["Mehr"], "timetable menu")
        tap(app.buttons["Woche"], "Woche")
        XCTAssertTrue(app.staticTexts["KW 43"].waitForExistence(timeout: 3))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["KW 44"].waitForExistence(timeout: 3), "swipe should show next week")
        tab(app, "Stundenplan")
        XCTAssertTrue(app.staticTexts["KW 43"].waitForExistence(timeout: 3), "tapping the tab again should go back to today")
        XCTAssertTrue(app.tabBars.buttons["Aufgaben"].isHittable, "the tab bar should stay full size")
        shot(app, "120-timetable-back-to-today")
    }

    /// Another app opening meldeplanner://melden only shows the subject picker; nothing is recorded.
    func test13_meldenLinkNeverRecordsByItself() {
        let app = launch(seed: true)
        let melden = app.buttons["Meldung erfassen"].firstMatch
        XCTAssertTrue(melden.waitForExistence(timeout: 5))
        let before = melden.value as? String
        app.open(URL(string: "meldeplanner://melden")!)
        XCTAssertTrue(app.buttons["Ohne Fach erfassen"].waitForExistence(timeout: 5), "the link should open the subject picker")
        shot(app, "130-melden-link-picker")
        tap(app.buttons["Abbrechen"].firstMatch, "Abbrechen")
        XCTAssertTrue(melden.waitForExistence(timeout: 3))
        XCTAssertEqual(melden.value as? String, before, "the link must not record a Meldung")
    }

    /// Settings → Google Drive: the sign-in button when the build has a Google client ID,
    /// otherwise a note that it isn't available yet (never both).
    func test14_googleDriveBackupScreen() {
        let app = launch(seed: true)
        // iPhone: Mehr > Verbindungen; iPad: its own sidebar entry.
        if device != "ipad" { tab(app, "Mehr") }
        let drive = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Google Drive'")).firstMatch
        for _ in 0..<6 where !drive.isHittable { app.swipeUp() }
        shot(app, "140-connections")
        guard tap(drive, "Google Drive row") else { return }
        let signIn = app.buttons["Mit Google anmelden"]
        let unavailable = app.staticTexts["In dieser Version noch nicht verfügbar."]
        XCTAssertTrue(signIn.waitForExistence(timeout: 3) || unavailable.exists)
        XCTAssertFalse(signIn.exists && unavailable.exists)
        shot(app, "141-google-drive")
    }
}
