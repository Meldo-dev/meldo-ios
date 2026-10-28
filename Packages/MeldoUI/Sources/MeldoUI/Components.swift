import MeldeCore
import MeldoKit
import MeldoState
import SwiftUI

/// Opaque content card. Content surfaces are not glass, so text stays readable.
public struct Card<Content: View>: View {
    public var title: String?
    public var systemImage: String?
    @ViewBuilder public var content: Content

    public init(title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingM) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .labelStyle(CardHeaderLabelStyle(showsIcon: systemImage != nil))
            }
            content
        }
        .padding(DS.spacingL)
        // Fills its grid cell, so cards in one row line up at the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: .rect(cornerRadius: DS.cardRadius, style: .continuous)
        )
    }
}

private struct CardHeaderLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.spacingS) {
            if showsIcon {
                configuration.icon.foregroundStyle(.tint)
            }
            configuration.title
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

/// Circular progress for goals. Animates unless Reduce Motion is on.
public struct ProgressRing: View {
    public var progress: Double
    public var lineWidth: CGFloat = 10
    public var tint: Color = .accentColor

    public init(progress: Double, lineWidth: CGFloat = 10, tint: Color = .accentColor) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.tint = tint
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(duration: 0.6), value: progress)
        }
        .accessibilityElement()
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// Colored circle with the subject's symbol.
public struct SubjectIcon: View {
    public var subject: Subject?
    public var size: CGFloat = 36

    public init(subject: Subject? = nil, size: CGFloat = 36) {
        self.subject = subject
        self.size = size
    }

    public var body: some View {
        let color = subject?.color.color ?? .gray
        Image(systemName: subject?.symbolName ?? "questionmark")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: .circle)
            .accessibilityHidden(true)
    }
}

/// One timetable occurrence as a row.
public struct LessonRow: View {
    public var occurrence: FfiOccurrence
    public var subject: Subject?
    public var isCurrent = false

    public init(occurrence: FfiOccurrence, subject: Subject? = nil, isCurrent: Bool = false) {
        self.occurrence = occurrence
        self.subject = subject
        self.isCurrent = isCurrent
    }

    public var body: some View {
        HStack(spacing: DS.spacingM) {
            SubjectIcon(subject: subject)
            VStack(alignment: .leading, spacing: 2) {
                Text(subject?.name ?? L("Unbekanntes Fach"))
                    .font(.body.weight(.semibold))
                    .strikethrough(occurrence.cancelled)
                HStack(spacing: DS.spacingS) {
                    Text(TimeText.range(occurrence.startMinute, occurrence.endMinute))
                        .monospacedDigit()
                    if let room = occurrence.room {
                        Text(verbatim: "· \(room)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if occurrence.cancelled {
                Badge(text: L("Entfällt"), color: .red)
            } else if occurrence.substituted {
                Badge(text: L("Vertretung"), color: .orange)
            } else if isCurrent {
                Badge(text: L("Jetzt"), color: subject?.color.color ?? .accentColor)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

public struct Badge: View {
    public var text: String
    public var color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, DS.spacingS)
            .padding(.vertical, DS.spacingXS)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}

public enum TimeText: Sendable {
    public static func clock(_ minuteOfDay: some BinaryInteger) -> String {
        let m = Int(minuteOfDay)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    public static func range(_ start: some BinaryInteger, _ end: some BinaryInteger) -> String {
        "\(clock(start))–\(clock(end))"
    }
}

/// Weekday names in the app language, Monday first.
public enum WeekdayText: Sendable {
    public static func short(_ index: Int) -> String {
        mondayFirst(calendar.shortStandaloneWeekdaySymbols)[index]
    }

    public static func full(_ index: Int) -> String {
        mondayFirst(calendar.standaloneWeekdaySymbols)[index]
    }

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Localization.locale
        return c
    }

    /// Foundation lists Sunday first.
    private static func mondayFirst(_ sundayFirst: [String]) -> [String] {
        Array(sundayFirst.dropFirst()) + sundayFirst.prefix(1)
    }
}
