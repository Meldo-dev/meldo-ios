import MeldoKit
import MeldoState
import SwiftUI

/// Spacing and shape tokens. One scale for the whole app keeps rhythm consistent.
public enum DS: Sendable {
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingM: CGFloat = 12
    public static let spacingL: CGFloat = 16
    public static let spacingXL: CGFloat = 24
    public static let cardRadius: CGFloat = 24
    public static let rowRadius: CGFloat = 16

    /// Curated SF Symbols for subjects.
    public static let subjectSymbols = [
        "book.closed", "function", "x.squareroot", "globe.europe.africa", "atom",
        "flask", "leaf", "pawprint", "paintpalette", "music.note", "figure.run",
        "theatermasks", "building.columns", "text.book.closed", "character.book.closed",
        "laptopcomputer", "chart.line.uptrend.xyaxis", "scalemass", "cross.case", "hands.and.sparkles",
    ]
}

/// Grouped background with the theme's wash. Content stays on opaque cards for readability;
/// glass is reserved for navigation and controls.
public struct ThemedBackground: View {

    public init() {
    }
    @Environment(AppModel.self) private var model

    public var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            if let wash = model.preferences.theme.wash {
                LinearGradient(
                    colors: [wash.opacity(0.10), .clear],
                    startPoint: .top, endPoint: .center
                )
            }
        }
        .ignoresSafeArea()
    }
}
