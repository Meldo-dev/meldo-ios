import MeldeCore
import MeldoKit
import SwiftUI
import WidgetKit

/// A snapshot of the stored data for widgets that only display it.
struct DataEntry: TimelineEntry {
    var date: Date
    var data: AppData?
}

struct DataProvider: TimelineProvider {
    func placeholder(in context: Context) -> DataEntry { DataEntry(date: .now, data: nil) }

    func getSnapshot(in context: Context, completion: @escaping (DataEntry) -> Void) {
        completion(DataEntry(date: .now, data: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DataEntry>) -> Void) {
        let data = load()
        // Every 15 minutes, so the current lesson and countdowns stay right; the
        // app also reloads widgets whenever data changes.
        let entries = (0..<8).map { step in
            DataEntry(date: Date().addingTimeInterval(TimeInterval(step * 15 * 60)), data: data)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func load() -> AppData? {
        guard let store = LocalStore.sharedIfAvailable(), let data = try? store.load() else { return nil }
        Localization.apply(data.preferences.language)
        return data
    }
}

private struct NotConnected: View {
    var body: some View {
        Text(L("Öffne Meldo einmal, um das Widget zu verbinden."))
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Today's timetable

struct TodayScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeldoSchedule", provider: DataProvider()) { entry in
            TodayScheduleView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Stundenplan heute")
        .description("Deine Stunden heute, Ausfälle durchgestrichen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct TodayScheduleView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DataEntry

    var body: some View {
        if let data = entry.data {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: entry.date)
            let minute = calendar.component(.hour, from: entry.date) * 60 + calendar.component(.minute, from: entry.date)
            let occurrences = (try? timetableOccurrencesOn(
                timetable: MeldeEngine.timetable(data, calendar: calendar),
                date: FfiDate(day, calendar: calendar)
            )) ?? []
            let holiday = data.holidays.first {
                calendar.startOfDay(for: $0.firstDay) <= day && day <= calendar.startOfDay(for: $0.lastDay)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localization.locale)))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "tablecells").foregroundStyle(.secondary)
                }
                if let holiday {
                    Label(holiday.name, systemImage: "sun.horizon.fill")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.42, green: 0.52, blue: 0.77))
                    Text(L("bis \(holiday.lastDay.formatted(.dateTime.day().month(.twoDigits).locale(Localization.locale)))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NextSchoolDay(data: data, after: entry.date)
                } else if occurrences.isEmpty {
                    Text(L("Heute kein Unterricht.")).font(.subheadline).foregroundStyle(.secondary)
                    NextSchoolDay(data: data, after: entry.date)
                } else {
                    let upcoming = occurrences.filter { Int($0.endMinute) > minute }
                    let shown = (upcoming.isEmpty ? occurrences : upcoming).prefix(family == .systemLarge ? 9 : 4)
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, o in
                        let subject = MeldeEngine.subject(data, id: o.subjectId)
                        let running = Int(o.startMinute) <= minute && minute < Int(o.endMinute)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(o.cancelled ? Color.red : (o.substituted ? Color.green : Color.secondary.opacity(0.5)))
                                .frame(width: 3)
                            Text(String(format: "%02d:%02d", Int(o.startMinute) / 60, Int(o.startMinute) % 60))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(subject?.name ?? L("Unterricht"))
                                .font(.subheadline.weight(running ? .bold : .regular))
                                .strikethrough(o.cancelled)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let room = o.room {
                                Text(room).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 18)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            NotConnected()
        }
    }
}

/// On a free day or in the holidays: when school continues, with which lesson.
private struct NextSchoolDay: View {
    let data: AppData
    let after: Date

    var body: some View {
        let calendar = Calendar.current
        if let next = MeldeEngine.nextLesson(data, after: after, calendar: calendar),
           let day = next.date.date(in: calendar),
           let start = calendar.date(minuteOfDay: Int(next.startMinute), on: day) {
            let time = start.formatted(Date.FormatStyle(locale: Localization.locale).weekday(.abbreviated).hour().minute())
            let name = MeldeEngine.subject(data, id: next.subjectId)?.name ?? L("Unterricht")
            Text(L("Danach: \(time) \(name)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Homework

struct HomeworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeldoHomework", provider: DataProvider()) { entry in
            HomeworkWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
                .widgetURL(DeepLink.homework)
        }
        .configurationDisplayName("Hausaufgaben")
        .description("Was bald fällig ist.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct HomeworkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DataEntry

    var body: some View {
        if let data = entry.data {
            let open = data.tasks
                .filter { $0.kind == .homework && !$0.isDone }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            VStack(alignment: .leading, spacing: 6) {
                Label(L("Hausaufgaben"), systemImage: "book.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                if open.isEmpty {
                    Spacer(minLength: 0)
                    Text(L("Alles erledigt.")).font(.headline)
                    Spacer(minLength: 0)
                } else if family == .systemSmall {
                    Spacer(minLength: 0)
                    Text(open.count, format: .number)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(open.first?.title ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    ForEach(open.prefix(4)) { task in
                        HStack(spacing: 6) {
                            Image(systemName: "circle").font(.caption).foregroundStyle(.secondary)
                            Text(task.title).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 0)
                            if let due = task.dueDate {
                                Text(due.formatted(.dateTime.weekday(.abbreviated).locale(Localization.locale)))
                                    .font(.caption)
                                    .foregroundStyle(due < Calendar.current.startOfDay(for: entry.date) ? Color.red : Color.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            NotConnected()
        }
    }
}
