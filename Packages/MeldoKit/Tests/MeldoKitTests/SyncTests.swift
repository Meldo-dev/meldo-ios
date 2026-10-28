import Foundation
import Testing
@testable import MeldoKit

@Suite("Sync merge")
struct SyncTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    /// A device's data after `change`, stamped at `time` like `LocalStore.update` does.
    func edit(_ base: AppData, at time: Date, _ change: (inout AppData) -> Void) -> AppData {
        var next = base
        change(&next)
        SyncMerge.record(from: base, to: &next, at: time)
        return next
    }

    @Test func writesAreStampedAndDeletionsRemembered() {
        let math = Subject(name: "Mathe")
        let added = edit(AppData(), at: at(1)) { $0.subjects.append(math) }
        #expect(added.sync.stamps["subjects:\(math.id.uuidString)"] == at(1))
        let removed = edit(added, at: at(2)) { $0.subjects.removeAll() }
        #expect(removed.sync.stamps["subjects:\(math.id.uuidString)"] == nil)
        #expect(removed.sync.tombstones["subjects:\(math.id.uuidString)"] == at(2))
        // Writing the same data again changes nothing.
        #expect(edit(removed, at: at(3)) { _ in }.sync == removed.sync)
    }

    @Test func editsOnTwoDevicesAreBothKept() {
        let base = edit(AppData(), at: at(1)) { $0.subjects.append(Subject(name: "Mathe")) }
        let phone = edit(base, at: at(2)) { $0.grades.append(GradeEntry(subjectID: $0.subjects[0].id, value: 2, written: true, date: t0)) }
        let ipad = edit(base, at: at(3)) { $0.subjects.append(Subject(name: "Bio")) }
        let merged = SyncMerge.merge(local: phone, remote: ipad)
        #expect(merged.subjects.map(\.name) == ["Mathe", "Bio"])
        #expect(merged.grades.count == 1)
        // Both orders give the same items.
        #expect(Set(SyncMerge.merge(local: ipad, remote: phone).subjects.map(\.id)) == Set(merged.subjects.map(\.id)))
    }

    @Test func newerEditOfTheSameItemWins() {
        let base = edit(AppData(), at: at(1)) { $0.subjects.append(Subject(name: "Mathe")) }
        let older = edit(base, at: at(2)) { $0.subjects[0].name = "Mathematik" }
        let newer = edit(base, at: at(5)) { $0.subjects[0].name = "Mathe LK" }
        #expect(SyncMerge.merge(local: older, remote: newer).subjects[0].name == "Mathe LK")
        #expect(SyncMerge.merge(local: newer, remote: older).subjects[0].name == "Mathe LK")
    }

    @Test func deletionBeatsOlderEditButNotNewerOne() {
        let base = edit(AppData(), at: at(1)) { $0.subjects.append(Subject(name: "Mathe")) }
        let deleted = edit(base, at: at(5)) { $0.subjects.removeAll() }
        let editedBefore = edit(base, at: at(3)) { $0.subjects[0].name = "Mathematik" }
        let editedAfter = edit(base, at: at(9)) { $0.subjects[0].name = "Mathematik" }
        #expect(SyncMerge.merge(local: editedBefore, remote: deleted).subjects.isEmpty)
        #expect(SyncMerge.merge(local: deleted, remote: editedBefore).subjects.isEmpty)
        #expect(SyncMerge.merge(local: deleted, remote: editedAfter).subjects.map(\.name) == ["Mathematik"])
    }

    @Test func singleValuesAndDeviceSettings() {
        let base = AppData()
        let phone = edit(base, at: at(2)) { $0.preferences.weeklyGoal = 10; $0.preferences.appIcon = .night; $0.dismissedImports = ["untis:1"] }
        let ipad = edit(base, at: at(4)) { $0.preferences.weeklyGoal = 12; $0.dismissedImports = ["teams:2"] }
        let merged = SyncMerge.merge(local: phone, remote: ipad)
        #expect(merged.preferences.weeklyGoal == 12)
        #expect(merged.preferences.appIcon == .night, "the app icon is set per device")
        #expect(merged.dismissedImports == ["untis:1", "teams:2"])
    }

    @Test func settingsChangedOnDifferentDevicesAreBothKept() {
        let base = edit(AppData(), at: at(1)) { $0.preferences.weeklyGoal = 8 }
        let phone = edit(base, at: at(2)) { $0.preferences.studentName = "Yavuz"; $0.preferences.className = "10b" }
        let ipad = edit(base, at: at(5)) { $0.preferences.appearance = .dark; $0.preferences.weeklyGoal = nil }
        for merged in [SyncMerge.merge(local: phone, remote: ipad), SyncMerge.merge(local: ipad, remote: phone)] {
            #expect(merged.preferences.studentName == "Yavuz", "the name entered on the phone survives a later iPad change")
            #expect(merged.preferences.className == "10b")
            #expect(merged.preferences.appearance == .dark)
            #expect(merged.preferences.weeklyGoal == nil, "clearing a setting syncs too")
        }
    }

    @Test func storeStampsItsWritesButNotMerges() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "melde-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalStore(url: url)
        let math = Subject(name: "Mathe")
        try store.update { $0.subjects.append(math) }
        let written = try store.load()
        #expect(written.sync.stamps["subjects:\(math.id.uuidString)"] != nil)
        try store.update(stamping: false) { $0.subjects[0].name = "Mathematik" }
        #expect(try store.load().sync.stamps == written.sync.stamps)
    }

    @Test func aClockRunningAheadDoesNotWinForever() {
        let math = Subject(name: "Mathe")
        let base = edit(AppData(), at: at(1)) { $0.subjects.append(math) }
        // The other device's clock is a year ahead.
        let ahead = edit(base, at: at(365 * 86_400)) { $0.subjects[0].name = "Mathe LK" }
        let merged = SyncMerge.merge(local: base, remote: ahead)
        #expect(merged.subjects.first?.name == "Mathe LK")
        // This device edits afterwards with its correct clock: its edit is stamped after
        // everything it has seen, so it wins on both devices.
        let later = edit(merged, at: at(60)) { $0.subjects[0].name = "Mathematik" }
        #expect(SyncMerge.merge(local: later, remote: ahead).subjects.first?.name == "Mathematik")
        #expect(SyncMerge.merge(local: ahead, remote: later).subjects.first?.name == "Mathematik")
    }
}
