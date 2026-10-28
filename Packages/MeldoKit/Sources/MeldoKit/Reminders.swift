import Foundation
import UserNotifications

/// Local notifications for task reminders. Local notifications need no paid
/// developer account, unlike remote push.
public enum Reminders: Sendable {
    private static func id(for taskID: UUID) -> String { "task-\(taskID.uuidString)" }

    /// Asks for permission the first time a reminder is set. Returns whether alerts are allowed.
    public static func requestAuthorization() async -> Bool {
        guard let center = UNUserNotificationCenter.app else { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    public static func schedule(_ task: SchoolTask, subjectName: String?) {
        cancel(taskID: task.id)
        guard let at = task.reminderAt, at > Date(), !task.isDone else { return }
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = subjectName.map { L("\($0) · noch offen") } ?? L("Noch offen")
        content.sound = .default
        content.threadIdentifier = "tasks"
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        let request = UNNotificationRequest(
            identifier: id(for: task.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        UNUserNotificationCenter.app?.add(request)
    }

    public static func cancel(taskID: UUID) {
        guard let center = UNUserNotificationCenter.app else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id(for: taskID)])
        center.removeDeliveredNotifications(withIdentifiers: [id(for: taskID)])
    }
}
