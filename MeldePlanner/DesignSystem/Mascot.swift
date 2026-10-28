import SwiftUI

/// Meldo, the raised-hand mascot. Purely decorative: hidden from
/// VoiceOver, hidden entirely when the student turns the mascot off, and the
/// wave animation respects Reduce Motion.
struct Mascot: View {
    enum Mood: String {
        case wave, cheer, sleep
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var mood: Mood
    var size: CGFloat = 96
    @State private var waves = 0

    var body: some View {
        if model.preferences.showMascot {
            Image("Meldo-\(mood.rawValue)")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .phaseAnimator([0.0, -9.0, 7.0, -4.0, 0.0], trigger: waves) { view, angle in
                    view.rotationEffect(.degrees(mood == .sleep ? 0 : angle), anchor: .bottom)
                } animation: { _ in .spring(duration: 0.28, bounce: 0.4) }
                .onAppear { if !reduceMotion { waves += 1 } }
                .onTapGesture { if !reduceMotion { waves += 1 } }
                .accessibilityHidden(true)
        }
    }
}
