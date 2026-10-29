import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Timetable laid out like WebUntis, in Meldo's design: period numbers with
/// bell times, blocks as long as the lessons (teacher, subject, room), changes
/// in Untis colors, parallel groups folded into one block with a count beside
/// it. The menu (top right) switches between day, 2 days, 3 days and week and
/// jumps to a date; the pages scroll sideways with the finger, one week (or
/// one set of days) at a time.
struct TimetableView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.features) private var features
    /// Bumped by tapping the Stundenplan tab again.
    @Environment(\.tabReselections) private var todayRequest
    @AppStorage("timetable.mode") private var mode = TimetableMode.week
    /// Weeks from this one (week view). Optional because the scroll view reports it.
    @State private var weekPage: Int? = 0
    /// Pages of `mode.dayCount` school days from today (day, 2 and 3 day views).
    @State private var dayPage: Int? = 0
    @State private var selected: TimetableBlock?
    @State private var creating = false
    @State private var managingSubjects = false
    @State private var choosingDate = false
    @State private var homeworkFor: HomeworkPrefill?
    /// Set by "Heute" and the tab re-tap; the page showing today scrolls to the time line once.
    @State private var showNow = false
    @State private var showingColors = false

    var body: some View {
        VStack(spacing: 0) {
            // The system's paging scroll: the page follows the finger, a slow drag
            // shows the next week coming in, and it can be caught and reversed.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages, id: \.self) { page in
                        TimetableDaysPage(
                            days: days(onPage: page, mode: mode),
                            detail: detail,
                            showNow: $showNow,
                            onSelect: { selected = $0 }
                        )
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: mode == .week ? $weekPage : $dayPage)
            .scrollIndicators(.hidden)
            .id(mode)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: mode) { old, _ in
                // Stay where the student was: the new view starts at the first day shown before.
                if let first = days(onPage: (old == .week ? weekPage : dayPage) ?? 0, mode: old).first {
                    show(first)
                }
            }
            .overlay {
                if model.lessons.isEmpty && model.data.untisTimetable == nil {
                    emptyState
                }
            }
        }
        .background(ThemedBackground())
        .onChange(of: todayRequest) { goToday() }
        .navigationTitle(L("Stundenplan"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { menu }
        }
        .sheet(item: $selected) { block in
            TimetableBlockSheet(block: block) { subjectID in
                selected = nil
                homeworkFor = HomeworkPrefill(subjectID: subjectID)
            }
        }
        .sheet(isPresented: $creating) {
            LessonEditorView(lesson: nil, weekday: model.calendar.mondayIndex(of: shownDays.first ?? model.currentDate))
        }
        .sheet(item: $homeworkFor) { prefill in
            features.destination(.newTask(kind: .homework, subjectID: prefill.subjectID))
        }
        .sheet(isPresented: $managingSubjects) {
            NavigationStack { features.destination(.page("subjects")) }
        }
        .sheet(isPresented: $choosingDate) {
            GoToDateSheet(start: shownDays.first ?? model.currentDate) { go(to: $0) }
        }
    }

    /// Like Untis: go to a date, pick the view, and the rarer actions.
    private var menu: some View {
        Menu {
            Button(L("Gehe zu Datum"), systemImage: "calendar.badge.clock") { choosingDate = true }
            Button(L("Heute"), systemImage: "smallcircle.filled.circle", action: goToday)
            Section(L("Ansicht")) {
                Picker(L("Ansicht"), selection: $mode) {
                    ForEach(TimetableMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Button(L("Stunde hinzufügen"), systemImage: "plus") { creating = true }
                    .disabled(model.subjects.isEmpty)
                if features.has(.page("subjects")) {
                    Button(L("Fächer"), systemImage: "books.vertical") { managingSubjects = true }
                }
                Button(L("Was bedeuten die Farben?"), systemImage: "paintpalette") { showingColors = true }
            }
        } label: {
            Label(L("Mehr"), systemImage: "ellipsis")
        }
        // The colors are explained in the tour and here, not in a bar under the grid.
        .popover(isPresented: $showingColors) {
            TimetableLegend(vertical: true)
                .padding(DS.spacingL)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// First steps when there is nothing to show yet.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(L("Keine Stunden"), systemImage: "tablecells")
        } description: {
            if model.subjects.isEmpty {
                Text(L("Lege zuerst unter „Fächer“ deine Fächer an."))
            } else {
                let day = WeekdayText.full(model.calendar.mondayIndex(of: shownDays.first ?? model.currentDate) % 7)
                Text(L("Füge die Stunden für \(day) hinzu."))
            }
        } actions: {
            if model.subjects.isEmpty {
                if features.has(.page("subjects")) {
                    Button(L("Fächer"), systemImage: "books.vertical") { managingSubjects = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                Button(L("Stunde hinzufügen"), systemImage: "plus") { creating = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: DS.cardRadius))
        .padding(DS.spacingXL)
    }

    private var detail: BlockDetail {
        switch mode {
        case .day: .full
        case .twoDays, .threeDays: .medium
        case .week: sizeClass == .regular ? .medium : .compact
        }
    }

    /// Half a year back, a year ahead (about 200 and 400 school days in the day views).
    private var pages: ClosedRange<Int> {
        mode == .week ? -26...52 : (-200 / mode.dayCount)...(400 / mode.dayCount)
    }

    private var shownDays: [Date] {
        days(onPage: (mode == .week ? weekPage : dayPage) ?? 0, mode: mode)
    }

    private func days(onPage page: Int, mode: TimetableMode) -> [Date] {
        switch mode {
        case .week:
            let monday = monday(weekOffset: page)
            let count = model.hasSaturdayLessons ? 6 : 5
            return (0..<count).compactMap { model.calendar.date(byAdding: .day, value: $0, to: monday) }
        default:
            return (0..<mode.dayCount).map { schoolDay(offset: page * mode.dayCount + $0) }
        }
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.45)
    }

    private func goToday() {
        withAnimation(pageAnimation) { weekPage = 0; dayPage = 0 }
        showNow = true
    }

    private func go(to date: Date) {
        withAnimation(pageAnimation) { show(date) }
    }

    /// The pages that contain `date`, in the week view and in the day views.
    private func show(_ date: Date) {
        let calendar = model.calendar
        let target = calendar.startOfDay(for: date)
        let thisMonday = monday(weekOffset: 0)
        let targetMonday = calendar.date(byAdding: .day, value: -calendar.mondayIndex(of: target), to: target) ?? target
        weekPage = (calendar.dateComponents([.day], from: thisMonday, to: targetMonday).day ?? 0) / 7
        let offset = Double(schoolDayOffset(to: target)) / Double(mode == .week ? 1 : mode.dayCount)
        dayPage = Int(offset.rounded(.down))
    }

    /// Monday of the week `offset` weeks from this one.
    private func monday(weekOffset offset: Int) -> Date {
        let today = model.calendar.startOfDay(for: model.currentDate)
        let thisMonday = model.calendar.date(byAdding: .day, value: -model.calendar.mondayIndex(of: today), to: today) ?? today
        return model.calendar.date(byAdding: .day, value: offset * 7, to: thisMonday) ?? thisMonday
    }

    private func isSchoolDay(_ date: Date) -> Bool {
        let index = model.calendar.mondayIndex(of: date)
        return index < 5 || (index == 5 && model.hasSaturdayLessons)
    }

    /// The school day `offset` school days from today (weekends skipped).
    private func schoolDay(offset: Int) -> Date {
        let calendar = model.calendar
        var day = calendar.startOfDay(for: model.currentDate)
        while !isSchoolDay(day) { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        var remaining = abs(offset)
        let direction = offset < 0 ? -1 : 1
        while remaining > 0 {
            day = calendar.date(byAdding: .day, value: direction, to: day) ?? day
            if isSchoolDay(day) { remaining -= 1 }
        }
        return day
    }

    /// School days between today and `date` (negative for the past).
    private func schoolDayOffset(to date: Date) -> Int {
        let calendar = model.calendar
        var day = calendar.startOfDay(for: model.currentDate)
        while !isSchoolDay(day) { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        let direction = date < day ? -1 : 1
        var count = 0
        while !calendar.isDate(day, inSameDayAs: date), abs(count) < 400 {
            day = calendar.date(byAdding: .day, value: direction, to: day) ?? day
            if isSchoolDay(day) { count += direction }
            if direction > 0 ? day > date : day < date { break }
        }
        return count
    }
}

enum TimetableMode: String, CaseIterable, Identifiable {
    case day, twoDays, threeDays, week
    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .day: 1
        case .twoDays: 2
        case .threeDays: 3
        case .week: 5
        }
    }

    var title: String {
        switch self {
        case .day: L("Tag")
        case .twoDays: L("2 Tage")
        case .threeDays: L("3 Tage")
        case .week: L("Woche")
        }
    }

    var symbol: String {
        switch self {
        case .day: "square"
        case .twoDays: "rectangle.split.2x1"
        case .threeDays: "rectangle.split.3x1"
        case .week: "calendar"
        }
    }
}

/// Subject to preselect when adding homework from a lesson.
private struct HomeworkPrefill: Identifiable {
    let id = UUID()
    let subjectID: UUID?
}

/// Jump to any date, like "Go to Date" in Untis.
private struct GoToDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    var onGo: (Date) -> Void

    init(start: Date, onGo: @escaping (Date) -> Void) {
        _start = State(initialValue: start)
        self.onGo = onGo
    }

    var body: some View {
        NavigationStack {
            DatePicker(L("Datum"), selection: $start, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Localization.locale)
                .padding()
                .navigationTitle(L("Gehe zu Datum"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Abbrechen"), role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Anzeigen")) {
                            onGo(start)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Grid

/// Vertical scale of the grid: which minutes are shown and how tall they are.
private struct GridMetrics {
    var start: Int
    var end: Int
    var pointsPerMinute: CGFloat

    // In CGFloat: synced minutes can be anything, and an Int difference could overflow.
    func y(_ minute: Int) -> CGFloat { (CGFloat(minute) - CGFloat(start)) * pointsPerMinute }
    var height: CGFloat { y(end) }

    /// From the first bell to the last block of the shown days (at least six periods).
    @MainActor static func make(model: AppModel, days: [Date], pointsPerMinute: CGFloat) -> GridMetrics {
        let bells = model.bellSchedule
        let blocks = days.flatMap { model.timetableBlocks(on: $0) }
        let first = min(bells.first?.startMinute ?? 8 * 60, blocks.map(\.startMinute).min() ?? 8 * 60)
        let sixth = bells.prefix(6).last?.endMinute ?? 13 * 60
        let last = max(sixth, blocks.map(\.endMinute).max() ?? sixth)
        return GridMetrics(start: first, end: last, pointsPerMinute: pointsPerMinute)
    }
}

/// One page: the week number in the corner (like "W 45 / Nov" in Untis), a
/// header per day, and the scrolling grid.
private struct TimetableDaysPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let days: [Date]
    let detail: BlockDetail
    /// The student asked for today: scroll to the time line, then reset.
    @Binding var showNow: Bool
    var onSelect: (TimetableBlock) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(edge: .top)
    /// Height the grid can use; on a big screen the day is stretched to fill it.
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        let base: CGFloat = detail == .full ? 1.7 : (sizeClass == .regular ? 1.5 : 1.3)
        let minutes = GridMetrics.make(model: model, days: days, pointsPerMinute: 1).height
        // No empty band under the last lesson; the Melden button floats over the grid.
        let room = DS.spacingS
        let fill = minutes > 0 ? (visibleHeight - room) / minutes : 0
        let metrics = GridMetrics.make(model: model, days: days, pointsPerMinute: max(base, fill))
        let first = days.first ?? model.currentDate
        let week = model.isoCalendar.component(.weekOfYear, from: first)
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("KW \(week)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(first.formatted(.dateTime.month(.abbreviated).locale(Localization.locale)))
                        .font(.headline)
                }
                .frame(width: TimeAxis.width, alignment: .leading)
                ForEach(days, id: \.self) { day in
                    DayHeader(date: day, wide: detail == .full)
                        .frame(maxWidth: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, DS.spacingS)
            ScrollView {
                HStack(alignment: .top, spacing: 3) {
                    TimeAxis(metrics: metrics)
                    ForEach(days, id: \.self) { day in
                        DayGrid(date: day, metrics: metrics, detail: detail, onSelect: onSelect)
                    }
                }
                .padding(.bottom, DS.spacingS)
                // Blocks have a fixed height per minute; the detail sheet shows everything larger.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            .scrollPosition($position)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
            // Only on request: scrolling by itself would also minimize the iPhone tab bar.
            .onAppear { if showNow { scrollToNow(metrics) } }
            .onChange(of: showNow) {
                guard showNow else { return }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0)) { scrollToNow(metrics) }
            }
            .overlay {
                if let limit = model.untisVisibleUntil, first > limit {
                    LimitNotice(limit: limit)
                }
            }
        }
        .padding(.horizontal, DS.spacingS)
        .padding(.top, DS.spacingXS)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

extension TimetableDaysPage {
    /// Puts the time line a little below the top, so the running lesson is in view.
    fileprivate func scrollToNow(_ metrics: GridMetrics) {
        let now = model.currentDate
        // The page sliding out isn't today's; leave the request for the one sliding in.
        guard days.contains(where: { model.calendar.isDate($0, inSameDayAs: now) }) else { return }
        showNow = false
        let minute = model.calendar.component(.hour, from: now) * 60 + model.calendar.component(.minute, from: now)
        guard minute > metrics.start, minute <= metrics.end else { return }
        position.scrollTo(y: max(metrics.y(minute) - 120, 0))
    }
}

/// The school only lets students see the timetable up to a certain day.
private struct LimitNotice: View {
    let limit: Date

    var body: some View {
        ContentUnavailableView {
            Label(L("Noch nicht freigegeben"), systemImage: "lock")
        } description: {
            let day = limit.formatted(.dateTime.day().month(.wide).locale(Localization.locale))
            Text(L("Deine Schule zeigt den Stundenplan nur bis \(day)."))
        }
        .background(.regularMaterial, in: .rect(cornerRadius: DS.cardRadius))
        .padding(DS.spacingXL)
    }
}

private struct DayHeader: View {
    @Environment(AppModel.self) private var model
    let date: Date
    let wide: Bool

    var body: some View {
        let isToday = model.calendar.isDate(date, inSameDayAs: model.currentDate)
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(wide ? .wide : .abbreviated).locale(Localization.locale)))
                .font(.caption)
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.accentColor : .primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isToday ? .isSelected : [])
    }
}

/// Period numbers with their bell times, like the left column in Untis.
private struct TimeAxis: View {
    static let width: CGFloat = 46
    @Environment(AppModel.self) private var model
    let metrics: GridMetrics

    var body: some View {
        ZStack(alignment: .top) {
            let bells = model.bellSchedule
            ForEach(Array(bells.enumerated()), id: \.offset) { index, bell in
                let next = index + 1 < bells.count ? bells[index + 1].startMinute : nil
                if bell.startMinute >= metrics.start, bell.endMinute <= metrics.end {
                    VStack(spacing: 0) {
                        Text(TimeText.clock(bell.startMinute))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(bell.name)
                            .font(.title3)
                        Spacer(minLength: 0)
                        if next != bell.endMinute {
                            Text(TimeText.clock(bell.endMinute))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .monospacedDigit()
                    .frame(width: Self.width, height: metrics.y(bell.endMinute) - metrics.y(bell.startMinute))
                    .offset(y: metrics.y(bell.startMinute))
                }
            }
        }
        .frame(width: Self.width, height: metrics.height, alignment: .top)
        // Every block already says its time.
        .accessibilityHidden(true)
    }
}

enum BlockDetail {
    case compact, medium, full
}

/// One day as a column: period lines, lesson blocks, holidays in blue and a
/// line for the current time.
private struct DayGrid: View {
    @Environment(AppModel.self) private var model
    let date: Date
    let metrics: GridMetrics
    let detail: BlockDetail
    var onSelect: (TimetableBlock) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(gridLines, id: \.self) { minute in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 0.5)
                        .offset(y: metrics.y(minute))
                }
                if detail == .full {
                    ForEach(breaks, id: \.self) { gap in
                        BreakBand(minutes: gap.end - gap.start)
                            .frame(height: metrics.y(gap.end) - metrics.y(gap.start))
                            .offset(y: metrics.y(gap.start))
                    }
                }
                if let holiday = model.holiday(on: date) {
                    HolidayColumn(holiday: holiday, detail: detail)
                } else {
                    ForEach(model.timetableBlocks(on: date)) { block in
                        let width = geo.size.width * block.widthShare
                        Button { onSelect(block) } label: {
                            TimetableBlockView(block: block, detail: detail, narrow: block.widthShare < 0.99 && detail != .full)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(block.alternatives.isEmpty ? L("Zum Bearbeiten tippen") : L("Tippen, um deinen Kurs zu wählen"))
                        .frame(width: max(width - 3, 10), height: max(metrics.y(block.endMinute) - metrics.y(block.startMinute) - 3, 18))
                        .offset(x: geo.size.width * block.xShare, y: metrics.y(block.startMinute) + 1.5)
                    }
                }
                TimelineView(.everyMinute) { _ in
                    let now = model.currentDate
                    let minute = model.calendar.component(.hour, from: now) * 60 + model.calendar.component(.minute, from: now)
                    if model.calendar.isDate(now, inSameDayAs: date), minute >= metrics.start, minute <= metrics.end {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .offset(y: metrics.y(minute))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(height: metrics.height)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localization.locale)))
    }

    /// A line at every period start and end inside the shown range.
    private var gridLines: [Int] {
        let minutes = model.bellSchedule.flatMap { [$0.startMinute, $0.endMinute] }
        return Array(Set(minutes)).filter { $0 >= metrics.start && $0 <= metrics.end }.sorted()
    }

    struct Gap: Hashable {
        var start: Int
        var end: Int
    }

    /// Gaps between consecutive bells that are within the shown range.
    private var breaks: [Gap] {
        let bells = model.bellSchedule
        guard bells.count > 1 else { return [] }
        return zip(bells, bells.dropFirst()).compactMap { a, b in
            let gap = AppModel.gap(from: a.endMinute, to: b.startMinute)
            guard gap >= 10, gap != .max, a.endMinute >= metrics.start, b.startMinute <= metrics.end else { return nil }
            return Gap(start: a.endMinute, end: b.startMinute)
        }
    }
}

/// Break label in the day view; breaks are otherwise just a gap.
private struct BreakBand: View {
    let minutes: Int

    var body: some View {
        Color.clear
            .overlay {
                Text(L("Pause · \(minutes) min"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
    }
}

/// Holidays fill the whole column in blue, like WebUntis.
private struct HolidayColumn: View {
    let holiday: Holiday
    let detail: BlockDetail

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.untisHoliday)
            .overlay {
                VStack(spacing: DS.spacingXS) {
                    Image(systemName: "lock.fill")
                    Text(holiday.name)
                        .font(detail == .compact ? .caption2.weight(.semibold) : .headline)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                    Text(HolidayText.range(holiday))
                        .font(.caption2)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .padding(DS.spacingXS)
            }
            .accessibilityElement(children: .combine)
    }
}

/// A lesson block in the WebUntis style: subject, teacher, room; changed room
/// or teacher on a green label; exams brown-orange with a yellow frame;
/// cancelled crossed out with a red frame. Small icons for homework and notes,
/// and a narrow column with the number of parallel groups.
private struct TimetableBlockView: View {
    let block: TimetableBlock
    let detail: BlockDetail
    /// Shares its time with other blocks side by side: no room for the teacher.
    var narrow = false

    var body: some View {
        let style = BlockStyle(kind: block.kind)
        HStack(spacing: 2) {
            content(style)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(style.fill, in: .rect(cornerRadius: 6, style: .continuous))
                .overlay {
                    if let border = style.border {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(border, lineWidth: 2)
                    }
                }
                // Large text must not run into the next lesson.
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
            if !block.alternatives.isEmpty {
                // "+1": more courses at this time (a bare "1" read like a lesson number).
                Text("+\(block.alternatives.count)")
                    .font(.caption2.weight(.semibold))
                    .frame(width: detail == .compact ? 12 : 16)
                    .frame(maxHeight: .infinity)
                    .background(Color.untisLesson.opacity(0.7), in: .rect(cornerRadius: 4, style: .continuous))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func content(_ style: BlockStyle) -> some View {
        HStack(spacing: 0) {
            // The thin bar inside the left edge, like WebUntis.
            Capsule()
                .fill(style.stripe)
                .frame(width: 3)
                .padding(.vertical, 5)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 1) {
                if detail == .full {
                    Text(block.subjectName)
                        .font(.headline)
                        .strikethrough(block.kind == .cancelled)
                        .lineLimit(1)
                }
                // The subject leads in every block, so the week scans by subject;
                // the teacher (green when substituted) and the room follow.
                if detail != .full {
                    label(block.shortTitle, font: detail == .compact ? .caption.weight(.bold) : .subheadline.weight(.bold),
                          highlighted: false, lines: block.isEvent ? 4 : 1)
                }
                if !block.teacher.isEmpty, !narrow || block.teacherChanged {
                    label(block.teacher, font: detail == .compact ? .caption2 : .caption, highlighted: block.teacherChanged)
                }
                if let room = block.room {
                    label(room, font: detail == .compact ? .caption2 : .caption, highlighted: block.roomChanged)
                }
                if detail == .full, let info = block.info {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, detail == .compact ? 4 : 6)
            .padding(.trailing, 3)
            .padding(.vertical, 4)
        }
        // Icons sit in the corner instead of their own row, so they never shrink the text.
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 3) {
                if block.kind == .exam {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                if block.hasHomework {
                    Image(systemName: "house.fill")
                }
                if block.info != nil, detail != .full {
                    Image(systemName: "info.circle.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(.primary.opacity(0.75))
            .padding(4)
            .accessibilityHidden(true)
        }
    }

    /// One line of the block; changed values sit on a green label like in Untis.
    private func label(_ text: String, font: Font, highlighted: Bool, lines: Int = 1) -> some View {
        Text(text)
            .font(font)
            .strikethrough(block.kind == .cancelled)
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .padding(.horizontal, highlighted ? 3 : 0)
            .background(highlighted ? Color.untisChange : .clear, in: .rect(cornerRadius: 3))
            .lineLimit(lines)
            .minimumScaleFactor(0.7)
    }

    private var accessibilityText: String {
        var parts = [block.subjectName, TimeText.range(block.startMinute, block.endMinute)]
        if !block.teacher.isEmpty { parts.append(block.teacher) }
        if let room = block.room { parts.append(room) }
        if let status = BlockStyle.label(for: block.kind) { parts.append(status) }
        if block.roomChanged, block.kind != .roomChange { parts.append(L("Raumänderung")) }
        if block.hasHomework { parts.append(L("Hausaufgabe fällig")) }
        if !block.alternatives.isEmpty { parts.append(L("Parallele Kurse zur Auswahl")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Detail

/// Lesson details. Parallel groups get a tab each (like WebUntis); the
/// student marks their own with "Das ist mein Kurs".
private struct TimetableBlockSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.features) private var features
    @Environment(\.dismiss) private var dismiss
    let block: TimetableBlock
    var onHomework: (UUID?) -> Void
    @State private var tab = 0
    @State private var editingLesson: Lesson?

    private var options: [TimetableBlock] { [block] + block.alternatives }

    var body: some View {
        let shown = options[min(tab, options.count - 1)]
        NavigationStack {
            List {
                if options.count > 1 {
                    Picker(L("Kurs"), selection: $tab) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            Text(option.teacher.isEmpty ? option.shortTitle : "\(option.shortTitle) · \(option.teacher)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                // Right under the switcher: further down it sat below the fold, so picking a
                // course and tapping Fertig saved nothing.
                if options.count > 1 {
                    Section {
                        if tab == 0 {
                            Label(L("Dein Kurs"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Button(L("Das ist mein Kurs"), systemImage: "checkmark.circle") {
                                model.chooseCourse(shown, among: options)
                                dismiss()
                            }
                        }
                    } footer: {
                        Text(L("Meldo zeigt deinen Kurs ab jetzt jede Woche zu dieser Zeit."))
                    }
                }
                Section {
                    HStack(spacing: DS.spacingM) {
                        SubjectIcon(subject: model.subject(shown.subjectID), size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shown.subjectName).font(.title3.weight(.semibold))
                            Text(shown.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localization.locale)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let status = BlockStyle.label(for: shown.kind) {
                        let style = BlockStyle(kind: shown.kind)
                        Label(status, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(style.border ?? Color.untisChange)
                    }
                }
                Section {
                    LabeledContent(L("Zeit"), value: TimeText.range(shown.startMinute, shown.endMinute))
                    if !shown.teacher.isEmpty {
                        LabeledContent(L("Lehrkraft"), value: shown.teacher)
                    }
                    if let room = shown.room {
                        if let original = shown.originalRoom {
                            LabeledContent(L("Raum"), value: L("\(room) statt \(original)"))
                        } else {
                            LabeledContent(L("Raum"), value: room)
                        }
                    }
                    if let info = shown.info {
                        Text(info)
                    }
                }
                Section {
                    if features.has(.newTask(kind: .homework, subjectID: nil)) {
                        Button(L("Hausaufgabe eintragen"), systemImage: "book") { onHomework(shown.subjectID) }
                    }
                    if let id = shown.lessonID, let lesson = model.lessons.first(where: { $0.id == id }) {
                        Button(L("Bearbeiten"), systemImage: "pencil") { editingLesson = lesson }
                    }
                }
            }
            // No title: the header row already names the subject and date ("D" alone said little).
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig")) { dismiss() }
                }
            }
            .sheet(item: $editingLesson) { LessonEditorView(lesson: $0, weekday: $0.weekday) }
        }
        .presentationDetents([.medium, .large])
    }
}
