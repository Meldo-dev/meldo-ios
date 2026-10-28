import AppIntents
import SwiftUI
import WidgetKit

/// Control Center and Lock Screen button (iOS 18+): one tap records a Meldung
/// for the current lesson, even with the phone locked.
struct MeldenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Surfaces.controlKind) {
            ControlWidgetButton(action: LogParticipationIntent()) {
                Label(L("Melden"), systemImage: "hand.raised.fill")
            }
        }
        .displayName("Melden")
        .description("Erfasst eine Meldung für die laufende Stunde.")
    }
}
