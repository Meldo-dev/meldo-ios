import AppIntents
import MeldeCore
import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widget: current or next lesson, this week's
/// Meldungen against the goal, and a one-tap Melden button during lessons.
struct MeldoTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Surfaces.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Meldo")
        .description("Laufende Stunde, Meldungen dieser Woche und Melden mit einem Tipp.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayEntry: TimelineEntry {
    struct LessonInfo {
        let name: String
        let color: SubjectColor
        let symbol: String
        let start: Date
        let end: Date
    }

    let date: Date
    /// `false` when the widget cannot read the app's data (no App Group).
    let isAvailable: Bool
    let current: LessonInfo?
    let next: LessonInfo?
    let lessonCount: Int
    let weekTotal: Int
    let goal: Int?
    let homeworkDue: Int
    let laterToday: [LessonInfo]
    /// The accent the student picked in Meldo (orange by default).
    var tint: Color = .meldoOrange
    /// Ferien today: name and last day. The widget says so instead of offering Melden.
    var holiday: (name: String, lastDay: Date)?

    static let placeholder = TodayEntry(
        date: .now, isAvailable: true,
        current: LessonInfo(name: "Mathe", color: .blue, symbol: "function", start: .now, end: .now.addingTimeInterval(1800)),
        next: nil, lessonCount: 2, weekTotal: 9, goal: 12, homeworkDue: 1, laterToday: []
    )
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now, data: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let data = load()
        let calendar = Calendar.current
        let now = Date()
        // A new entry at every lesson start and end today, so the widget flips without the app.
        var moments: [Date] = [now]
        if let data {
            let day = calendar.startOfDay(for: now)
            let occurrences = (try? timetableOccurrencesOn(
                timetable: MeldeEngine.timetable(data, calendar: calendar),
                date: FfiDate(now, calendar: calendar)
            )) ?? []
            for o in occurrences {
                for minute in [Int(o.startMinute), Int(o.endMinute) + Int(MeldeEngine.participationGraceMinutes)] {
                    if let moment = calendar.date(minuteOfDay: minute, on: day), moment > now {
                        moments.append(moment)
                    }
                }
            }
        }
        let entries = moments.sorted().map { entry(at: $0, data: data) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }

    private func load() -> AppData? {
        guard let store = LocalStore.sharedIfAvailable(), let data = try? store.load() else { return nil }
        Localization.apply(data.preferences.language)
        return data
    }

    private func entry(at date: Date, data: AppData?) -> TodayEntry {
        guard let data else {
            return TodayEntry(date: date, isAvailable: false, current: nil, next: nil, lessonCount: 0,
                              weekTotal: 0, goal: nil, homeworkDue: 0, laterToday: [])
        }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        func info(_ o: FfiOccurrence) -> TodayEntry.LessonInfo? {
            let subject = MeldeEngine.subject(data, id: o.subjectId)
            guard let start = calendar.date(minuteOfDay: Int(o.startMinute), on: calendar.startOfDay(for: o.date.date(in: calendar) ?? day)),
                  let end = calendar.date(minuteOfDay: Int(o.endMinute), on: calendar.startOfDay(for: o.date.date(in: calendar) ?? day))
            else { return nil }
            return .init(name: subject?.name ?? L("Unterricht"), color: subject?.color ?? .blue,
                         symbol: subject?.symbolName ?? "book.closed", start: start, end: end)
        }
        let currentOccurrence = MeldeEngine.participationLesson(data, at: date, calendar: calendar)
        let nextOccurrence = MeldeEngine.nextLesson(data, after: date, calendar: calendar)
        let todays = (try? timetableOccurrencesOn(timetable: MeldeEngine.timetable(data, calendar: calendar), date: FfiDate(date, calendar: calendar))) ?? []
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let later = todays.filter { !$0.cancelled && Int($0.startMinute) > minute }.prefix(3).compactMap(info)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let homework = data.tasks.filter { $0.kind == .homework && !$0.isDone && ($0.dueDate.map { $0 <= tomorrow } ?? false) }.count
        return TodayEntry(
            date: date,
            isAvailable: true,
            current: currentOccurrence.flatMap(info),
            next: nextOccurrence.flatMap(info),
            lessonCount: currentOccurrence.map { MeldeEngine.count(data, lessonID: $0.lessonId, on: date, calendar: calendar) } ?? 0,
            weekTotal: Int(MeldeEngine.weekSummary(data, containing: date, calendar: calendar)?.total ?? 0),
            goal: data.preferences.weeklyGoal,
            homeworkDue: homework,
            laterToday: Array(later),
            tint: data.preferences.theme.tint,
            holiday: data.holidays
                .first { calendar.startOfDay(for: $0.firstDay) <= day && day <= calendar.startOfDay(for: $0.lastDay) }
                .map { ($0.name, $0.lastDay) }
        )
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        Group {
            if !entry.isAvailable {
                UnavailableView()
            } else {
                switch family {
                case .accessoryCircular: CircularView(entry: entry)
                case .accessoryRectangular: RectangularView(entry: entry)
                case .accessoryInline: Label(L("\(entry.weekTotal) diese Woche"), systemImage: "hand.raised.fill")
                case .systemMedium: MediumView(entry: entry)
                default: SmallView(entry: entry)
                }
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

private struct UnavailableView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.raised.fill").foregroundStyle(Color.meldoOrange)
            Text(L("Öffne Meldo einmal, um das Widget zu verbinden."))
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
}

/// The Melden button during a lesson; outside lessons a link that opens the subject picker.
private struct MeldenButton: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: TodayEntry

    var body: some View {
        if entry.current != nil {
            // Clear and tinted home screens render widgets "accented": colors become
            // white, so a filled indigo capsule would turn into a white blob that hides
            // its white label. There the button is a translucent capsule with an
            // accent-tinted label instead.
            let accented = renderingMode == .accented
            Button(intent: LogParticipationIntent()) {
                Label(L("Melden"), systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accented ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                    .widgetAccentable()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        accented ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(entry.tint),
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: DeepLink.melden) {
                Label(L("Melden"), systemImage: "hand.raised")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(entry.tint.opacity(0.15), in: .capsule)
            }
        }
    }
}

private struct LessonHeader: View {
    let entry: TodayEntry

    var body: some View {
        if let current = entry.current {
            VStack(alignment: .leading, spacing: 2) {
                Label(current.name, systemImage: current.symbol)
                    .font(.headline)
                    .foregroundStyle(current.color.color)
                    .lineLimit(1)
                Text(L("\(entry.lessonCount)× gemeldet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let next = entry.next {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Als Nächstes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(next.name, systemImage: next.symbol)
                    .font(.headline)
                    .foregroundStyle(next.color.color)
                    .lineLimit(1)
                LessonStartText(start: next.start)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(L("Heute kein Unterricht."))
                .font(.headline)
        }
    }
}

private struct WeekLine: View {
    let entry: TodayEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.raised.fill").foregroundStyle(Color.meldoOrange)
            if let goal = entry.goal {
                Text(L("\(entry.weekTotal) von \(goal)"))
            } else {
                Text(L("\(entry.weekTotal) diese Woche"))
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
    }
}

private struct SmallView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let holiday = entry.holiday, entry.current == nil {
                // Ferien: nothing to log, so no Melden button; just when school starts again.
                VStack(alignment: .leading, spacing: 2) {
                    Label(holiday.name, systemImage: "sun.horizon.fill")
                        .font(.headline)
                        .foregroundStyle(Color.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(L("bis \(holiday.lastDay.formatted(.dateTime.day().month(.twoDigits).locale(Localization.locale)))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let next = entry.next {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Danach")).font(.caption2).foregroundStyle(.secondary)
                        Text(next.name).font(.caption.weight(.semibold)).lineLimit(1)
                        LessonStartText(start: next.start).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                LessonHeader(entry: entry)
                Spacer(minLength: 0)
                WeekLine(entry: entry)
                MeldenButton(entry: entry)
            }
        }
    }
}

/// When the next lesson starts: a countdown within the hour, otherwise weekday and time
/// ("Mo. 09:35"); "7 Tg., 15 Std." took a moment to understand.
private struct LessonStartText: View {
    let start: Date

    var body: some View {
        if start.timeIntervalSinceNow < 3600 {
            Text(start, style: .relative)
        } else if Calendar.current.isDateInToday(start) {
            Text(start, style: .time)
        } else {
            Text(start.formatted(Date.FormatStyle(locale: Localization.locale).weekday(.abbreviated).hour().minute()))
        }
    }
}

private struct MediumView: View {
    let entry: TodayEntry

    var body: some View {
        HStack(spacing: 16) {
            SmallView(entry: entry)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Später heute")).font(.caption).foregroundStyle(.secondary)
                if entry.laterToday.isEmpty {
                    Text(L("Keine weiteren Stunden.")).font(.caption)
                }
                ForEach(Array(entry.laterToday.enumerated()), id: \.offset) { _, lesson in
                    HStack(spacing: 6) {
                        Circle().fill(lesson.color.color).frame(width: 8, height: 8)
                        Text(lesson.name).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(lesson.start, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if entry.homeworkDue > 0 {
                    Link(destination: DeepLink.homework) {
                        Label(entry.homeworkDue == 1 ? L("1 Hausaufgabe bald fällig") : L("\(entry.homeworkDue) Hausaufgaben bald fällig"), systemImage: "book")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CircularView: View {
    let entry: TodayEntry

    var body: some View {
        if let goal = entry.goal {
            Gauge(value: Double(min(entry.weekTotal, goal)), in: 0...Double(max(goal, 1))) {
                Image(systemName: "hand.raised.fill")
            } currentValueLabel: {
                Text(entry.weekTotal, format: .number)
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "hand.raised.fill").font(.caption)
                    Text(entry.weekTotal, format: .number).font(.headline)
                }
            }
        }
    }
}

private struct RectangularView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let current = entry.current {
                Label(current.name, systemImage: current.symbol).font(.headline).lineLimit(1)
                Text(L("\(entry.lessonCount)× gemeldet · bis \(current.end.formatted(date: .omitted, time: .shortened))"))
                    .font(.caption)
            } else if let next = entry.next {
                Text(next.name).font(.headline).lineLimit(1)
                Text(L("Als Nächstes · \(next.start.formatted(date: .omitted, time: .shortened))")).font(.caption)
            } else {
                Text(L("Heute kein Unterricht.")).font(.headline)
            }
            Text(L("\(entry.weekTotal) Meldungen diese Woche")).font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
