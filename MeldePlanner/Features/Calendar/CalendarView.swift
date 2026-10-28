import MeldeCore
import SwiftUI

/// Month view with markers (flame on days with Meldungen, exams, homework,
/// absences, holidays in blue) and the picked day's lessons, exams,
/// homework, absences and Meldungen. On iPad the month and the day sit side by side.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The day the student picked; today (by the model's clock) until they pick one.
    @State private var picked: Date?
    @State private var monthOffset = 0

    private var date: Date { picked ?? model.currentDate }

    var body: some View {
        let layout = sizeClass == .regular
            ? AnyLayout(HStackLayout(alignment: .top, spacing: DS.spacingL))
            : AnyLayout(VStackLayout(spacing: DS.spacingL))
        ScrollView {
            layout {
                Card {
                    MonthGrid(month: month, selected: date, onSelect: { picked = $0 }, onShift: { monthOffset += $0 })
                }
                .frame(maxWidth: sizeClass == .regular ? 440 : .infinity)
                VStack(spacing: DS.spacingL) {
                    dayDetails
                }
            }
            .padding(DS.spacingL)
        }
        .background(ThemedBackground())
        .navigationTitle(L("Kalender"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Heute")) {
                    withAnimation { picked = nil; monthOffset = 0 }
                }
            }
        }
    }

    /// First day of the shown month.
    private var month: Date {
        let calendar = model.calendar
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: model.currentDate)) ?? model.currentDate
        return calendar.date(byAdding: .month, value: monthOffset, to: start) ?? start
    }

    @ViewBuilder
    private var dayDetails: some View {
        if let holiday = model.holiday(on: date) {
            HolidayBanner(holiday: holiday)
        }
        let blocks = model.timetableBlocks(on: date)
        Card(title: date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localization.locale)), systemImage: "tablecells") {
            if blocks.isEmpty {
                Text(L("Kein Unterricht an diesem Tag."))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: DS.spacingS) {
                    ForEach(blocks) { block in
                        BlockRow(block: block, showInfo: true)
                    }
                }
            }
        }
        let exams = model.untisExams(on: date)
        if !exams.isEmpty {
            Card(title: L("Prüfungen"), systemImage: "pencil.and.list.clipboard") {
                ForEach(exams) { exam in
                    UntisExamRow(exam: exam, now: model.currentDate)
                }
            }
        }
        let due = model.tasks(dueOn: date)
        if !due.isEmpty {
            Card(title: L("Fällig"), systemImage: "book") {
                ForEach(due) { task in
                    TaskRow(task: task, today: model.currentDate) {}
                }
            }
        }
        let absences = model.absences(on: date)
        if !absences.isEmpty {
            Card(title: L("Abwesenheiten"), systemImage: "person.crop.circle.badge.clock") {
                ForEach(absences) { absence in
                    AbsenceRow(absence: absence)
                }
            }
        }
        let entries = model.entries(on: date)
        if !entries.isEmpty {
            Card(title: L("Meldungen"), systemImage: "hand.raised") {
                // One row per subject with its count; long lists of single entries are hard to read.
                let groups = Dictionary(grouping: entries) { $0.subjectID }
                    .map { MeldungGroup(subjectID: $0.key, entries: $0.value.sorted { $0.recordedAt < $1.recordedAt }) }
                    .sorted { ($0.entries.first?.recordedAt ?? .distantPast) < ($1.entries.first?.recordedAt ?? .distantPast) }
                ForEach(groups) { group in
                    HStack {
                        SubjectIcon(subject: model.subject(group.subjectID), size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.subject(group.subjectID)?.name ?? L("Ohne Fach"))
                            Text(group.entries.map { $0.recordedAt.formatted(.dateTime.hour().minute()) }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(verbatim: "\(group.entries.count)×")
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .contextMenu {
                        if let last = group.entries.last {
                            Button(L("Letzte Meldung löschen"), systemImage: "trash", role: .destructive) {
                                model.deleteParticipation(last.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MeldungGroup: Identifiable {
    let subjectID: UUID?
    let entries: [ParticipationEntry]
    var id: String { subjectID?.uuidString ?? "none" }
}

/// A month of days, Monday first, with markers per day.
private struct MonthGrid: View {
    @Environment(AppModel.self) private var model
    let month: Date
    let selected: Date
    var onSelect: (Date) -> Void
    var onShift: (Int) -> Void

    private var days: [Date?] {
        let calendar = model.calendar
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let lead = calendar.mondayIndex(of: month)
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + dates.map { Optional($0) }
    }

    var body: some View {
        let streakDays = model.meldungDays
        VStack(spacing: DS.spacingS) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year().locale(Localization.locale)))
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                Button(L("Zurück"), systemImage: "chevron.left") { withAnimation { onShift(-1) } }
                    .labelStyle(.iconOnly)
                Button(L("Weiter"), systemImage: "chevron.right") { withAnimation { onShift(1) } }
                    .labelStyle(.iconOnly)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(WeekdayText.short(index))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            day: day,
                            isSelected: model.calendar.isDate(day, inSameDayAs: selected),
                            hasMeldung: streakDays.contains(model.calendar.startOfDay(for: day))
                        )
                        .onTapGesture { onSelect(day) }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
            CalendarLegend()
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -40 { withAnimation { onShift(1) } }
                if value.translation.width > 40 { withAnimation { onShift(-1) } }
            }
        )
    }
}

private struct DayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let isSelected: Bool
    let hasMeldung: Bool

    var body: some View {
        let isToday = model.calendar.isDate(day, inSameDayAs: model.currentDate)
        let holiday = model.holiday(on: day) != nil
        let exam = !model.untisExams(on: day).isEmpty
        let homework = !model.tasks(dueOn: day).filter { !$0.isDone }.isEmpty
        let absent = !model.absences(on: day).isEmpty
        VStack(spacing: 1) {
            Text(day.formatted(.dateTime.day()))
                .font(.callout.weight(isToday || isSelected ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                .frame(width: 30, height: 26)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
            HStack(spacing: 2) {
                if hasMeldung {
                    Image(systemName: "flame.fill").font(.system(size: 8)).foregroundStyle(.orange)
                }
                if exam { Circle().fill(Color.yellow).frame(width: 5, height: 5) }
                if homework { Circle().fill(Color.orange).frame(width: 5, height: 5) }
                if absent { Circle().fill(Color.red).frame(width: 5, height: 5) }
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(holiday ? Color.untisHoliday.opacity(0.25) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localization.locale)))
        .accessibilityValue(markers(holiday: holiday, exam: exam, homework: homework, absent: absent))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func markers(holiday: Bool, exam: Bool, homework: Bool, absent: Bool) -> String {
        var parts: [String] = []
        if hasMeldung { parts.append(L("Meldungen")) }
        if holiday { parts.append(L("Ferien")) }
        if exam { parts.append(L("Prüfung")) }
        if homework { parts.append(L("Hausaufgabe fällig")) }
        if absent { parts.append(L("Abwesend")) }
        return parts.joined(separator: ", ")
    }
}

private struct CalendarLegend: View {
    var body: some View {
        ViewThatFits {
            HStack(spacing: DS.spacingM) { items }
            VStack(alignment: .leading, spacing: DS.spacingXS) { items }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var items: some View {
        Label(L("Meldungen"), systemImage: "flame.fill").labelStyle(LegendLabelStyle(color: .orange))
        Label(L("Prüfung"), systemImage: "circle.fill").labelStyle(LegendLabelStyle(color: .yellow))
        Label(L("Hausaufgabe fällig"), systemImage: "circle.fill").labelStyle(LegendLabelStyle(color: .orange))
        Label(L("Abwesend"), systemImage: "circle.fill").labelStyle(LegendLabelStyle(color: .red))
    }
}

private struct LegendLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(color)
            configuration.title
        }
    }
}
