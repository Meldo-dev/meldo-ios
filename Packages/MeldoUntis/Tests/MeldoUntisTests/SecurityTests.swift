import Foundation
import MeldoKit
import MeldoState
import Testing
@testable import MeldoUntis

/// Regression tests for security fixes. Dummy data only.
@Suite("Security")
struct SecurityTests {
    /// Lead 3: an account switch that arrives by sync stops imports still running for the old
    /// account, so they can't store its secret or link again.
    @MainActor @Test func syncedAccountSwitchStopsRunningImports() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "meldo-security-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalStore(url: url)
        let model = AppModel(store: store)
        model.installUntis()
        model.mutate { $0.untis = UntisLink(server: "a.webuntis.com", loginName: "x", schoolName: "", user: "old") }
        let before = model.data
        var merged = model.data
        merged.untis = UntisLink(server: "b.webuntis.com", loginName: "x", schoolName: "", user: "new")
        try store.save(merged)
        let generation = model.untisGeneration
        model.applyMerged(since: before)
        #expect(model.data.untis?.user == "new")
        #expect(model.untisGeneration == generation + 1)
    }

    /// Lead 4: a failed automatic update waits before the next one.
    @Test func aWrongPasswordStopsAutomaticRetries() {
        #expect(AppModel.untisRetryDelay(after: .wrongCredentials, failures: 1) == .infinity)
    }

    @Test func failuresBackOffAndStayBounded() {
        #expect(AppModel.untisRetryDelay(after: .sessionExpired, failures: 1) == 30 * 60)
        #expect(AppModel.untisRetryDelay(after: .noLessons, failures: 1) == 30 * 60)
        let delays = (1...10).map { AppModel.untisRetryDelay(after: .network, failures: $0) }
        #expect(delays.first == 60)
        #expect(zip(delays, delays.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(delays.allSatisfy { $0 <= 30 * 60 })
    }

    /// A school login without a secret on this device fails (sessionExpired): the first automatic
    /// update counts the failure and pauses, the next one within the pause doesn't try again.
    @MainActor @Test func noAutomaticUpdateWhileWaiting() async {
        let model = AppModel(store: nil)
        let server = "pause-\(UUID().uuidString.prefix(8).lowercased()).webuntis.com"
        model.mutate { $0.untis = UntisLink(server: server, loginName: "x", schoolName: "", user: "", browserLogin: true) }
        await model.refreshUntisIfStale()
        #expect(model.untisFailures == 1)
        #expect(model.untisRetryAfter != nil)
        await model.refreshUntisIfStale()
        #expect(model.untisFailures == 1)
    }
}
