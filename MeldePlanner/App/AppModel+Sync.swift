import Foundation

extension AppModel {
    /// After a sync merged other devices' changes into the store: loads them and lets
    /// this device follow what happened on its other devices.
    func applyMerged(since before: AppData) {
        reloadFromDisk()
        // Exams deleted on another device: their PDFs go here too (unless another exam uses the file).
        let kept = Set(data.exams.map(\.fileName)), ids = Set(data.exams.map(\.id))
        for exam in before.exams where !ids.contains(exam.id) && !kept.contains(exam.fileName) {
            if let url = fileURL(for: exam) { try? FileManager.default.removeItem(at: url) }
        }
        // Disconnected on another device: this device's secrets go too.
        if let untis = before.untis, data.untis == nil {
            forgetUntisSecrets(untis)
        } else if let untis = before.untis, let now = data.untis, Self.keychainAccount(now) != Self.keychainAccount(untis) {
            // Another account or server now: the old account's secret goes (and imports still
            // running for it stop, so they can't store it again), the new login stays.
            forgetUntisSecrets(untis)
        }
        if before.teams != nil, data.teams == nil { forgetTeamsSecret() }
        // Reminders follow tasks deleted or changed on another device.
        let earlier = Set(before.tasks.map(\.id))
        for task in before.tasks where !data.tasks.contains(task) {
            if let now = data.tasks.first(where: { $0.id == task.id }) {
                Reminders.schedule(now, subjectName: subject(now.subjectID)?.name)
            } else {
                Reminders.cancel(taskID: task.id)
            }
        }
        for task in data.tasks where !earlier.contains(task.id) && task.reminderAt != nil {
            Reminders.schedule(task, subjectName: subject(task.subjectID)?.name)
        }
        Surfaces.reload()
        refreshSchedules()
    }
}
