import MeldoKit
import SwiftUI

/// Mehr → WebUntis: the import waits for Untis to approve Meldo as an integration
/// partner, so this build only says so. Data imported by an earlier version stays.
struct UntisPendingView: View {
    var body: some View {
        ContentUnavailableView {
            Label(L("Wartet auf Freigabe durch Untis"), systemImage: "hourglass")
        } description: {
            Text(L("In dieser Version und in den kommenden Versionen nicht verfügbar, bis Untis die Anbindung freigibt. Bis dahin trägst du deinen Stundenplan selbst ein."))
        }
        .navigationTitle(L("WebUntis"))
    }
}
