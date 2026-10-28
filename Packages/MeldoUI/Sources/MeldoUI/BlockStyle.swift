import MeldeCore
import MeldoKit
import MeldoState
import SwiftUI

/// Colors per change, shared with lists and the legend.
public struct BlockStyle: Sendable {
    public var fill: Color
    public var stripe: Color
    public var border: Color?
    /// The change color for lists and previews (green for changes, gray for regular lessons).
    public var accent: Color

    /// Like WebUntis: every lesson the same slate, exams brown-orange with a
    /// yellow frame, cancelled with a red frame; a change marks the changed
    /// value (room, teacher) green. `subjectColor` is kept for callers.
    public init(kind: TimetableBlock.Kind, subjectColor: Color = .gray) {
        switch kind {
        case .regular:
            fill = .untisLesson; stripe = Color.primary.opacity(0.55); border = nil; accent = .gray
        case .roomChange, .substitution:
            fill = .untisLesson; stripe = Color.primary.opacity(0.55); border = nil; accent = .untisChange
        case .exam:
            fill = .untisExamFill; stripe = .untisExam; border = .untisExam; accent = .untisExam
        case .cancelled:
            fill = .untisLesson.opacity(0.6); stripe = .untisCancelled; border = .untisCancelled; accent = .untisCancelled
        }
    }

    public static func label(for kind: TimetableBlock.Kind) -> String? {
        switch kind {
        case .regular: nil
        case .roomChange: L("Raumänderung")
        case .exam: L("Prüfung")
        case .cancelled: L("Entfall")
        case .substitution: L("Änderung")
        }
    }
}

extension Color {
    /// Lesson slate, adapting to light and dark mode.
    public static let untisLesson = Color(UIColor { @Sendable traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.35, blue: 0.40, alpha: 1)
            : UIColor(red: 0.86, green: 0.89, blue: 0.92, alpha: 1)
    })
    /// Exam blocks: brown-orange in dark mode, light apricot in light mode.
    public static let untisExamFill = Color(UIColor { @Sendable traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.43, green: 0.18, blue: 0.05, alpha: 1)
            : UIColor(red: 1.00, green: 0.87, blue: 0.74, alpha: 1)
    })
    /// WebUntis' change colors.
    public static let untisChange = Color(red: 0.0, green: 0.50, blue: 0.38)
    /// Exam frame: yellow in dark mode, deeper amber in light mode so it shows on the apricot fill.
    public static let untisExam = Color(UIColor { @Sendable traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.98, green: 0.70, blue: 0.10, alpha: 1)
            : UIColor(red: 0.80, green: 0.50, blue: 0.00, alpha: 1)
    })
    public static let untisCancelled = Color(red: 0.90, green: 0.21, blue: 0.37)
    /// The blue WebUntis uses for holidays.
    public static let untisHoliday = Color(red: 0.42, green: 0.52, blue: 0.77)
}

/// What the timetable colors mean (Untis colors). In the timetable's menu and the tour.
public struct TimetableLegend: View {
    public var vertical = false

    public init(vertical: Bool = false) {
        self.vertical = vertical
    }

    public var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.spacingS))
            : AnyLayout(HStackLayout(spacing: DS.spacingM))
        layout {
            item(.untisExam, L("Prüfung"))
            item(.untisChange, L("Änderung"))
            item(.untisCancelled, L("Entfall"))
            item(.untisHoliday, L("Ferien"))
        }
        .font(vertical ? .body : .caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: DS.spacingS) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 14)
            Text(text)
        }
    }
}
