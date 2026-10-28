import XCTest

/// Helpers for website screenshots of Meldo's widgets on a simulator. Not part of the
/// normal walk: the host starts Meldo with `-uitest-seed-store`, puts the widgets on the
/// last Home Screen page (SpringBoard's IconState.plist; adding them through the widget
/// gallery crashes SpringBoard on the simulator) and takes the screenshots itself
/// (`simctl io screenshot`). These tests only move SpringBoard to the right place.
final class WidgetShotsUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Shows the last Home Screen page, where the widgets are.
    func testShowWidgetPage() {
        XCUIDevice.shared.press(.home)
        wait(1)
        XCUIDevice.shared.press(.home)
        wait(1)
        let pill = springboard.otherElements["spotlight-pill"].firstMatch
        for _ in 0..<5 {
            // "Seite 3 von 3" / "Page 3 of 3": the last page.
            let parts = (pill.value as? String ?? "").split(separator: " ").compactMap { Int($0) }
            if parts.count == 2, parts[0] == parts[1] { break }
            springboard.swipeLeft()
            wait(1)
        }
        wait(2)
    }

    /// Locks and wakes the screen, so the host can capture the lesson's Live Activity.
    func testLock() {
        let lockButton = NSSelectorFromString("pressLockButton")
        XCUIDevice.shared.perform(lockButton)
        wait(1)
        XCUIDevice.shared.perform(lockButton)
        wait(2)
        // A fresh simulator has a system notification that would be in the picture.
        let notices = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Apple Intelligence'"))
        for _ in 0..<3 where notices.firstMatch.exists {
            notices.firstMatch.swipeLeft()
            let clear = springboard.buttons.matching(NSPredicate(format: "label IN {'Löschen', 'Clear', 'Entfernen'}")).firstMatch
            if clear.waitForExistence(timeout: 2) { clear.tap() }
            wait(1)
        }
        // iOS asks on the Lock Screen whether Meldo may keep showing Live Activities.
        let allow = springboard.buttons.matching(NSPredicate(format: "label IN {'Erlauben', 'Allow', 'Immer erlauben', 'Always Allow'}")).firstMatch
        if allow.exists {
            allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            wait(1)
        }
        wait(3)
    }
}
