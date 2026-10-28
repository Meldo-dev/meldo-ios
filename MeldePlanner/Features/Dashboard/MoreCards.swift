import Charts
import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// The lesson running now or coming next, with a live countdown.
struct NextLessonCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize

    var body: some View {
        let minute = model.calendar.component(.hour, from: now) * 60 + model.calendar.component(.minute, from: now)
        let today = model.calendar.startOfDay(for: now)
        let block = model.timetableBlocks(on: now).first { $0.endMinute > minute && $0.kind != .cancelled }
        Card(title: L("Nächste Stunde"), systemImage: "clock") {
            if let block {
                let running = block.startMinute <= minute
                let target = model.calendar.date(minuteOfDay: running ? block.endMinute : block.startMinute, on: today) ?? now
                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    Text(block.subjectName)
                        .font(size == .small ? .headline : .title3.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: DS.spacingXS) {
                        Text(running ? L("endet in") : L("beginnt in"))
                        Text(target, style: .relative)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if size != .small {
                        BlockRow(block: block, isCurrent: running)
                    }
                }
            } else if let next = model.nextLesson(after: now) {
                let name = model.subject(for: next)?.name ?? L("Unbekanntes Fach")
                let day = next.date.date(in: model.calendar) ?? now
                Text(name).font(.headline)
                Text(day.formatted(.dateTime.weekday(.wide).locale(Localization.locale)) + ", " + TimeText.clock(next.startMinute))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Keine weiteren Stunden."))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Meldungen per school day this week as a small bar chart.
struct WeekChartMiniCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize

    private struct Day: Identifiable {
        let index: Int
        let count: Int
        var id: Int { index }
    }

    var body: some View {
        let summary = model.weekSummary(containing: now)
        let days = (summary?.perDay ?? []).prefix(5).enumerated().map { Day(index: $0.offset, count: Int($0.element)) }
        let today = model.calendar.mondayIndex(of: now)
        Card(title: L("Wochenverlauf"), systemImage: "chart.bar.xaxis") {
            Chart(days) { day in
                BarMark(
                    x: .value(L("Tag"), WeekdayText.short(day.index)),
                    y: .value(L("Meldungen"), day.count)
                )
                .foregroundStyle(day.index == today ? Color.accentColor : Color.accentColor.opacity(0.35))
                .cornerRadius(4)
            }
            .chartYScale(domain: 0...max(days.map(\.count).max() ?? 0, 5))
            .chartYAxis(size == .small ? .hidden : .automatic)
            .frame(minHeight: size == .large ? 160 : 90)
            .accessibilityLabel(L("Meldungen pro Tag"))
        }
    }
}
