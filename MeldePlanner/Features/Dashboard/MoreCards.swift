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

/// How long until the next holidays, or how long they still last.
struct NextHolidayCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize

    var body: some View {
        let today = model.calendar.startOfDay(for: now)
        let holiday = model.upcomingHolidays(from: now).first
        Card(title: L("Nächste Ferien"), systemImage: "sun.horizon") {
            if let holiday {
                let running = holiday.firstDay <= today
                let target = running ? holiday.lastDay : holiday.firstDay
                let days = max(model.calendar.dateComponents([.day], from: today, to: model.calendar.startOfDay(for: target)).day ?? 0, 0)
                HStack(alignment: .firstTextBaseline, spacing: DS.spacingS) {
                    Text(days, format: .number)
                        .font(.system(size: size == .small ? 34 : 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.untisHoliday)
                    Text(running ? L("Tage Ferien übrig") : L("Tage bis dahin"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(holiday.name).font(.headline)
                if size != .small {
                    Text(HolidayText.range(holiday))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(model.data.untis == nil
                     ? L("Verbinde WebUntis, dann erscheinen hier die Ferien deiner Schule.")
                     : L("Keine Ferien eingetragen"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Open to-dos (not homework), check off in place.
struct TodosCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize
    @State private var adding = false

    var body: some View {
        let open = model.tasks.filter { $0.kind == .todo && !$0.isDone }
        Card(title: L("To-dos"), systemImage: "checklist") {
            if open.isEmpty {
                Text(L("Nichts zu tun"))
                    .foregroundStyle(.secondary)
            } else if size == .small {
                HStack(alignment: .firstTextBaseline, spacing: DS.spacingS) {
                    Text(open.count, format: .number)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text(L("offen")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(open.prefix(size == .large ? 8 : 3)) { task in
                        TaskRow(task: task, today: now) {}
                    }
                }
            }
            if size != .small {
                Button(L("To-do hinzufügen"), systemImage: "plus") { adding = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .sheet(isPresented: $adding) { TaskEditorView(task: nil, kind: .todo) }
    }
}

/// Estimated average from the student's own grades (Notenrechner).
struct GradesCard: View {
    @Environment(AppModel.self) private var model
    var size: CardSize

    var body: some View {
        Card(title: L("Notenschnitt"), systemImage: "graduationcap") {
            if let overall = model.overallGradeAverage {
                Text(model.gradeText(overall))
                    .font(.system(size: size == .small ? 34 : 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(L("geschätzt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if size != .small {
                    let graded = model.subjects.compactMap { subject in
                        model.subjectGradeText(for: subject.id).map { (subject, $0) }
                    }
                    ForEach(graded.prefix(size == .large ? 8 : 3), id: \.0.id) { subject, grade in
                        HStack {
                            Text(subject.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(grade).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
            } else {
                Text(L("Trag deine Noten ein, dann rechnet Meldo deinen Schnitt aus."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            NavigationLink(L("Notenrechner")) { GradesView() }
                .font(.subheadline.weight(.semibold))
        }
    }
}
