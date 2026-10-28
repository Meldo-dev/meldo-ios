import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Home: cards the student arranges and resizes ("Anpassen"), from a day
/// preview to school messages. Adapts to what the student has set up.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.features) private var features
    @State private var addingSubject = false
    @State private var editing = false

    var body: some View {
        TimelineView(.everyMinute) { _ in
            ScrollView {
                if model.subjects.isEmpty && model.data.untis == nil {
                    GettingStartedCard(addSubject: { addingSubject = true })
                        .frame(maxWidth: 560)
                        .padding(DS.spacingL)
                } else {
                    VStack(spacing: DS.spacingL) {
                        if !editing {
                            UnassignedCard(now: model.currentDate)
                            CheckInPromptCard()
                        }
                        CustomizableCardGrid(
                            slots: visibleSlots,
                            available: features.dashboardCards.map(\.kind),
                            editing: $editing,
                            title: { features.dashboardCard($0)?.title() ?? "" },
                            symbol: { features.dashboardCard($0)?.symbol ?? "square" },
                            save: save
                        ) { card, size in
                            features.dashboardCard(card)?.content(model.currentDate, size)
                        }
                    }
                    .padding(DS.spacingL)
                }
            }
            .background(ThemedBackground())
            .navigationTitle(greeting(for: model.currentDate))
            .toolbar {
                if !model.subjects.isEmpty || model.data.untis != nil {
                    ToolbarItem(placement: .primaryAction) { CustomizeButton(editing: $editing) }
                }
            }
        }
        .sheet(.newSubject, isPresented: $addingSubject)
    }

    /// Cards of this build, in the student's order. Without WebUntis, its cards would only
    /// say "connect WebUntis" three times; they stay hidden until then, except while
    /// arranging so they can be placed.
    private var visibleSlots: [CardSlot<DashboardCard>] {
        let layout = model.preferences.homeLayout.filter { features.dashboardCard($0.kind) != nil }
        guard model.data.untis == nil, !editing else { return layout }
        return layout.filter { features.dashboardCard($0.kind)?.needsUntis != true }
    }

    /// Saves the arrangement and keeps the slots of cards this build doesn't have.
    private func save(_ slots: [CardSlot<DashboardCard>]) {
        model.setHomeLayout(slots + model.preferences.homeLayout.filter { features.dashboardCard($0.kind) == nil })
    }

    private func greeting(for date: Date) -> String {
        switch model.calendar.component(.hour, from: date) {
        case 5..<11: L("Guten Morgen")
        case 11..<17: L("Hallo")
        case 17..<22: L("Guten Abend")
        default: L("Gute Nacht")
        }
    }
}

private struct GettingStartedCard: View {
    var addSubject: () -> Void

    var body: some View {
        Card(title: L("Los geht's"), systemImage: "sparkles") {
            HStack(alignment: .center, spacing: DS.spacingL) {
                Mascot(mood: .wave, size: 88)
                Text(L("Hi, ich bin Meldo! Lege deine Fächer und deinen Stundenplan an. Danach ordne ich jede Meldung automatisch der laufenden Stunde zu."))
                    .foregroundStyle(.secondary)
            }
            Button(action: addSubject) {
                Label(L("Erstes Fach anlegen"), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            RouteLink(.page("untis")) {
                Label(L("Mit WebUntis verbinden"), systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }
}

// MARK: - Day preview

/// Today's lessons with Untis changes in color; small shows only what's next.
struct TodayCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.features) private var features
    var now: Date
    var size: CardSize
    @State private var addingLesson = false

    private var newLesson: MeldoRoute { .newLesson(weekday: model.calendar.mondayIndex(of: now)) }

    private var minuteNow: Int {
        model.calendar.component(.hour, from: now) * 60 + model.calendar.component(.minute, from: now)
    }

    var body: some View {
        let blocks = model.timetableBlocks(on: now)
        let title = size == .small
            ? now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Localization.locale))
            : now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localization.locale))
        Card(title: title, systemImage: "sun.max") {
            if blocks.isEmpty, let holiday = model.holiday(on: now) {
                HStack(spacing: DS.spacingM) {
                    if size != .small { Mascot(mood: .sleep, size: 56) }
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
                        Text(holiday.name).font(.headline)
                        Text(HolidayText.range(holiday)).monospacedDigit().foregroundStyle(.secondary)
                        if size != .small { nextLessonText }
                    }
                }
            } else if blocks.isEmpty {
                if model.lessons.isEmpty && model.data.untisTimetable == nil {
                    Text(L("Noch keine Stunden im Stundenplan."))
                        .foregroundStyle(.secondary)
                    if features.has(newLesson) {
                        Button(L("Stunde hinzufügen"), systemImage: "plus") { addingLesson = true }
                            .buttonStyle(.glass)
                    }
                } else {
                    HStack(spacing: DS.spacingM) {
                        if size != .small { Mascot(mood: .sleep, size: 56) }
                        VStack(alignment: .leading, spacing: DS.spacingXS) {
                            Text(L("Heute kein Unterricht.")).font(.headline)
                            nextLessonText
                        }
                    }
                }
            } else if size == .small {
                let upcoming = blocks.first { $0.endMinute > minuteNow && $0.kind != .cancelled }
                if let block = upcoming {
                    Text(block.startMinute <= minuteNow ? L("Jetzt") : L("Als Nächstes"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BlockRow(block: block, isCurrent: block.startMinute <= minuteNow, compact: true)
                } else {
                    Text(L("Schulschluss für heute."))
                        .foregroundStyle(.secondary)
                }
            } else {
                let shown = size == .large ? blocks : Array(blocks.prefix(6))
                VStack(spacing: DS.spacingS) {
                    ForEach(shown) { block in
                        BlockRow(
                            block: block,
                            isCurrent: block.startMinute <= minuteNow && minuteNow < block.endMinute,
                            compact: false,
                            showInfo: size == .large
                        )
                        .opacity(block.endMinute <= minuteNow ? 0.5 : 1)
                    }
                }
                let more = blocks.count - shown.count
                if more > 0 {
                    Text(L("+\(more) weitere"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(newLesson, isPresented: $addingLesson)
    }

    @ViewBuilder
    private var nextLessonText: some View {
        if let next = model.nextLesson(after: now) {
            let name = model.subject(for: next)?.name ?? L("Unbekanntes Fach")
            let day = nextDayText(next)
            let time = TimeText.clock(next.startMinute)
            Text(L("Nächste Stunde: \(name), \(day) \(time)"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func nextDayText(_ next: FfiOccurrence) -> String {
        guard let date = next.date.date(in: model.calendar) else { return "" }
        if model.calendar.isDateInTomorrow(date) { return L("morgen") }
        return date.formatted(.dateTime.weekday(.wide).locale(Localization.locale))
    }
}

// MARK: - Week preview

private struct DayBlocks: Identifiable {
    let date: Date
    let blocks: [TimetableBlock]
    var id: Date { date }
}

/// The school week at a glance: one mini column per day, changes in color.
struct WeekPreviewCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize

    /// This week; from Saturday on, the next one.
    private var days: [Date] {
        let calendar = model.calendar
        let today = calendar.startOfDay(for: now)
        let index = calendar.mondayIndex(of: today)
        let monday = calendar.date(byAdding: .day, value: index >= 5 ? 7 - index : -index, to: today) ?? today
        return (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        let week = days.map { DayBlocks(date: $0, blocks: model.timetableBlocks(on: $0)) }
        let all = week.flatMap(\.blocks)
        Card(title: L("Woche"), systemImage: "calendar.day.timeline.left") {
            if size == .small {
                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    summaryLine(all, .exam, L("Prüfungen"))
                    summaryLine(all, .roomChange, L("Raumänderungen"))
                    summaryLine(all, .cancelled, L("Ausfälle"))
                    if !all.contains(where: { $0.kind != .regular }) {
                        Text(L("Keine Änderungen."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: DS.spacingXS) {
                    ForEach(week) { day in
                        dayColumn(day.date, day.blocks)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summaryLine(_ blocks: [TimetableBlock], _ kind: TimetableBlock.Kind, _ label: String) -> some View {
        let count = blocks.filter { $0.kind == kind }.count
        if count > 0 {
            let style = BlockStyle(kind: kind, subjectColor: .gray)
            HStack(spacing: DS.spacingXS) {
                Circle().fill(style.accent).frame(width: 8, height: 8)
                Text(verbatim: "\(count) \(label)").font(.subheadline)
            }
        }
    }

    private func dayColumn(_ day: Date, _ blocks: [TimetableBlock]) -> some View {
        let isToday = model.calendar.isDate(day, inSameDayAs: now)
        return VStack(spacing: 3) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Localization.locale)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
            if let holiday = model.holiday(on: day) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.untisHoliday)
                    .frame(height: size == .large ? 120 : 60)
                    .overlay {
                        if size == .large {
                            Text(holiday.name)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(-90))
                                .fixedSize()
                        }
                    }
            } else if blocks.isEmpty {
                Text(L("frei")).font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(blocks) { block in
                    let style = BlockStyle(kind: block.kind, subjectColor: model.subject(block.subjectID)?.color.color ?? .gray)
                    if size == .large {
                        Text(block.shortTitle)
                            .font(.caption2.weight(.semibold))
                            .strikethrough(block.kind == .cancelled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(style.fill, in: .rect(cornerRadius: 4))
                            .overlay {
                                if let border = style.border {
                                    RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 1.5)
                                }
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(style.accent)
                            .frame(height: 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(3)
        .background(isToday ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).locale(Localization.locale)))
        .accessibilityValue(blocks.map(\.subjectName).joined(separator: ", "))
    }
}

// MARK: - Participation

struct WeekParticipationCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize
    @State private var editingGoal = false

    var body: some View {
        let summary = model.weekSummary(containing: now)
        let total = Int(summary?.total ?? 0)
        let goal = model.preferences.weeklyGoal
        Card(title: size == .small ? L("Meldungen") : L("Meldungen diese Woche"), systemImage: "hand.raised") {
            HStack(spacing: DS.spacingXL) {
                ZStack {
                    ProgressRing(progress: goal.map { Double(total) / Double(max($0, 1)) } ?? 0)
                    VStack(spacing: 0) {
                        Text(total, format: .number)
                            .font(.title.weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if let goal {
                            Text(L("von \(goal)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: size == .small ? 80 : 96, height: size == .small ? 80 : 96)
                .frame(maxWidth: size == .small ? .infinity : nil)

                if size != .small {
                    VStack(alignment: .leading, spacing: DS.spacingS) {
                        if let goal {
                            let remaining = max(goal - total, 0)
                            Text(remaining == 0 ? L("Wochenziel erreicht.") : L("Noch \(remaining) bis zum Wochenziel."))
                                .foregroundStyle(.secondary)
                            if remaining == 0 {
                                Mascot(mood: .cheer, size: 52)
                            }
                        }
                        Button(goal == nil ? L("Wochenziel festlegen") : L("Ziel ändern")) { editingGoal = true }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                    .font(.subheadline)
                }
            }
            if size == .large {
                Text(L("Meldungen zählen deine Beteiligung. Die mündliche Note vergibt deine Lehrkraft."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $editingGoal) { WeeklyGoalSheet(now: now) }
    }
}

/// School days in a row with a Meldung, and on-time homework.
struct StreakCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize

    var body: some View {
        let streak = model.streak(asOf: now)
        let homework = model.homeworkStreak(asOf: now)
        Card(title: L("Serie"), systemImage: "flame") {
            HStack(spacing: DS.spacingM) {
                Image(systemName: "flame.fill")
                    .font(.system(size: size == .small ? 34 : 44))
                    .foregroundStyle(streak > 0 ? Color.orange.gradient : Color.secondary.gradient)
                    .symbolEffect(.bounce, value: streak)
                VStack(alignment: .leading, spacing: 2) {
                    Text(streak, format: .number)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(L("Schultage in Folge"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // One streak at a time: the homework streak only appears once there is one.
            if size != .small, homework > 0 {
                Label(L("\(homework) Tage pünktlich in Folge"), systemImage: "book")
                    .font(.subheadline)
                    .foregroundStyle(Color.orange)
            }
        }
    }
}

// MARK: - Exams, news, absences
