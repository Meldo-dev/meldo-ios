import Foundation
import UserNotifications

public nonisolated extension UNUserNotificationCenter {
    /// The notification center, or `nil` outside an app or app extension bundle
    /// (a unit-test runner has none, and asking for the center there stops the process).
    static var app: UNUserNotificationCenter? {
        let kind = Bundle.main.bundleURL.pathExtension
        return kind == "app" || kind == "appex" ? .current() : nil
    }
}
