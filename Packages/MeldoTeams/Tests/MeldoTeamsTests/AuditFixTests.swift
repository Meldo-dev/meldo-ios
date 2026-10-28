import Foundation
import MeldoKit
import MeldoState
import Testing
@testable import MeldoTeams

/// Regression tests for findings from earlier security reviews.
@Suite("Audit fixes: Teams")
struct AuditFixTests {
    @MainActor @Test func disconnectStopsRunningImports() {
        let model = AppModel(store: nil)
        let teams = model.teamsGeneration
        model.disconnectTeams()
        #expect(model.teamsGeneration == teams + 1)
    }
}
