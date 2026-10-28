import SwiftUI

/// Spacing and shape tokens. One scale for the whole app keeps rhythm consistent.
enum DS {
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let cardRadius: CGFloat = 24
    static let rowRadius: CGFloat = 16

    /// Curated SF Symbols for subjects.
    static let subjectSymbols = [
        "book.closed", "function", "x.squareroot", "globe.europe.africa", "atom",
        "flask", "leaf", "pawprint", "paintpalette", "music.note", "figure.run",
        "theatermasks", "building.columns", "text.book.closed", "character.book.closed",
        "laptopcomputer", "chart.line.uptrend.xyaxis", "scalemass", "cross.case", "hands.and.sparkles",
    ]
}

/// Grouped background with the theme's wash. Content stays on opaque cards for readability;
/// glass is reserved for navigation and controls.
struct ThemedBackground: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
