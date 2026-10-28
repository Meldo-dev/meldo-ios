import Charts
import MeldeCore
import SwiftUI
import WidgetKit

/// This week's Meldungen: against the goal (small) or per day with the most
/// active subject (medium). Real entries only; an empty week shows zeros.
struct MeldoStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeldoStats", provider: StatsProvider()) { entry in
            StatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Meldo Statistik")
        .description("Deine Meldungen diese Woche.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StatsEntry: TimelineEntry {
    var date: Date
    var isAvailable: Bool
    /// Monday to Friday.
    var perDay: [Int]
    var total: Int
    var goal: Int?
    var streak: Int
    var topSubject: String?
    var topColor: Color
    var tint: Color = .meldoOrange

    static let placeholder = StatsEntry(
        date: .now, isAvailable: true, perDay: [3, 1, 4, 2, 0], total: 10, goal: 12,
        streak: 4, topSubject: "Mathe", topColor: .blue
    )
}

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        // The app reloads widgets after every Meldung; refresh at midnight for the new day.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        completion(Timeline(entries: [entry(at: .now)], policy: .after(tomorrow)))
    }

    private func entry(at date: Date) -> StatsEntry {
        guard let store = LocalStore.sharedIfAvailable(), let data = try? store.load() else {
            return StatsEntry(date: date, isAvailable: false, perDay: [], total: 0, goal: nil, streak: 0, topSubject: nil, topColor: .gray)
        }
        Localization.apply(data.preferences.language)
        let calendar = Calendar.current
        let summary = MeldeEngine.weekSummary(data, containing: date, calendar: calendar)
        let top = summary?.perSubject.max { $0.count < $1.count }
        let subject = top.flatMap { MeldeEngine.subject(data, id: $0.subjectId) }
        let streak = (try? participationStreak(
            entries: MeldeEngine.entries(data, calendar: calendar),
            timetable: MeldeEngine.timetable(data, calendar: calendar),
            today: FfiDate(date, calendar: calendar)
        )) ?? 0
        return StatsEntry(
            date: date,
            isAvailable: true,
            perDay: (summary?.perDay.prefix(5).map { Int($0) }) ?? [0, 0, 0, 0, 0],
            total: Int(summary?.total ?? 0),
            goal: data.preferences.weeklyGoal,
            streak: Int(streak),
            topSubject: (top?.count ?? 0) > 0 ? subject?.name : nil,
            topColor: subject?.color.color ?? .gray,
            tint: data.preferences.theme.tint
        )
    }
}

struct StatsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatsEntry

    var body: some View {
        Group {
            if !entry.isAvailable {
                Text(L("Öffne Meldo einmal, um das Widget zu verbinden."))
                    .font(.caption)
                    .multilineTextAlignment(.center)
            } else if family == .accessoryCircular {
                Gauge(value: Double(min(entry.total, entry.goal ?? max(entry.total, 1))), in: 0...Double(max(entry.goal ?? max(entry.total, 1), 1))) {
                    Image(systemName: "hand.raised.fill")
                } currentValueLabel: {
                    Text(entry.total, format: .number)
                }
                .gaugeStyle(.accessoryCircular)
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Label(L("Meldungen"), systemImage: "hand.raised.fill")
                        .font(.headline)
                        .widgetAccentable()
                    if let goal = entry.goal {
                        Text(L("\(entry.total) von \(goal) diese Woche"))
                    } else {
                        Text(L("\(entry.total) diese Woche"))
                    }
                    Label(L("\(entry.streak) Schultage in Folge"), systemImage: "flame.fill")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if family == .accessoryInline {
                Label(L("\(entry.total) diese Woche · \(entry.streak) in Folge"), systemImage: "flame.fill")
            } else if family == .systemMedium {
                HStack(spacing: 16) {
                    summary
                    chart
                }
            } else {
                summary
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("Meldungen"), systemImage: "hand.raised.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.tint)
                .widgetAccentable()
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.total, format: .number)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let goal = entry.goal {
                    Text(L("von \(goal)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let goal = entry.goal {
                ProgressView(value: Double(min(entry.total, goal)), total: Double(max(goal, 1)))
                    .tint(entry.tint)
            }
            Label(L("\(entry.streak) Schultage in Folge"), systemImage: "flame.fill")
                .font(.caption2)
                .foregroundStyle(entry.streak > 0 ? Color.orange : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart(Array(entry.perDay.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value(L("Tag"), weekday(item.offset)),
                    y: .value(L("Meldungen"), item.element)
                )
                .foregroundStyle(entry.tint.gradient)
                .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            if let top = entry.topSubject {
                Label(top, systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(entry.topColor)
                    .lineLimit(1)
            }
        }
    }

    /// Short weekday in the app language, Monday first.
    private func weekday(_ index: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Localization.locale
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return symbols[(index + 1) % symbols.count]
    }
}
