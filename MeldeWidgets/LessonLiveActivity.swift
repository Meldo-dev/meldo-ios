import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

extension LessonActivityAttributes {
    /// Started by "Vorschau anzeigen" in Status (`LessonActivity.preview`).
    var isPreview: Bool { lessonID.hasPrefix("preview-") }
}

/// Lock Screen / Dynamic Island view of the running lesson.
struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { context in
            LessonActivityView(context: context)
                .padding(16)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let color = SubjectColor(rawValue: context.attributes.colorKey)?.color ?? .meldoOrange
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.subjectName, systemImage: context.attributes.symbolName)
                        .font(.headline)
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(L("\(context.state.count)×"))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        LessonTimeText(start: context.attributes.start, end: context.attributes.end)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if context.attributes.isPreview {
                            // The preview from Status must not record real Meldungen.
                            Label(L("Vorschau – nichts gespeichert."), systemImage: "hand.raised.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(intent: LogParticipationIntent()) {
                                Label(L("Melden"), systemImage: "hand.raised.fill")
                            }
                            .tint(Color.meldoOrange)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "hand.raised.fill").foregroundStyle(color)
            } compactTrailing: {
                Text(context.state.count, format: .number).monospacedDigit()
            } minimal: {
                Text(context.state.count, format: .number).monospacedDigit()
            }
        }
    }
}

private struct LessonActivityView: View {
    let context: ActivityViewContext<LessonActivityAttributes>

    var body: some View {
        let color = SubjectColor(rawValue: context.attributes.colorKey)?.color ?? .meldoOrange
        HStack(spacing: 14) {
            Image(systemName: context.attributes.symbolName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.16), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.subjectName).font(.headline)
                if context.isStale {
                    Text(L("Stunde vorbei")).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    LessonTimeText(start: context.attributes.start, end: context.attributes.end)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(context.attributes.isPreview ? L("Vorschau – nichts gespeichert.") : L("\(context.state.count)× gemeldet · \(context.state.weekTotal) diese Woche"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if context.attributes.isPreview {
                // Same look, but not a button: the preview from Status must not record real Meldungen.
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.meldoOrange.opacity(0.5), in: .circle)
                    .accessibilityLabel(L("Vorschau – nichts gespeichert."))
            } else {
                Button(intent: LogParticipationIntent()) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(Color.meldoOrange)
                .accessibilityLabel(L("Meldung erfassen"))
            }
        }
    }
}

/// The lesson's time for the Lock Screen and the Dynamic Island: its day and start
/// when it's more than an hour away (a "183:41" countdown says nothing), a countdown
/// to the bell within the last hour, and the time left while it runs.
private struct LessonTimeText: View {
    let start: Date
    let end: Date

    var body: some View {
        let now = Date()
        if now >= start {
            Text(timerInterval: start...end, countsDown: true).monospacedDigit()
        } else if start.timeIntervalSince(now) > 3600 {
            let style = Date.FormatStyle(locale: Localization.locale).weekday(.abbreviated).hour().minute()
            Text(L("Beginnt \(start.formatted(style))"))
        } else {
            HStack(spacing: 4) {
                Text(L("Beginnt in"))
                Text(timerInterval: now...start, countsDown: true).monospacedDigit()
            }
        }
    }
}

