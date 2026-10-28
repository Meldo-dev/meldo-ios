import Foundation
import MeldeCore

/// One block in the Untis-style timetable: a period, or a double period merged
/// across a short break. Built from the dated WebUntis periods where they
/// exist, otherwise from the student's own weekly lessons.
struct TimetableBlock: Identifiable, Hashable {
    enum Kind: Hashable {
        case regular, substitution, cancelled, exam, roomChange
    }

    var id: String
    var date: Date
    var startMinute: Int
    var endMinute: Int
    /// Short label for narrow columns, e.g. "MAT".
    var shortTitle: String
    var subjectName: String
    var teacher: String
    var room: String?
    var originalRoom: String?
    var kind: Kind
    var info: String?
    var subjectID: UUID?
    /// The student's own lesson, when the block comes from their timetable.
    var lessonID: UUID?
    /// Side-by-side layout when blocks overlap (e.g. a course and an event).
    var lane = 0
    var lanes = 1
    /// Horizontal position and width as fractions of the day column.
    var xShare = 0.0
    var widthShare = 1.0
    /// Parallel groups at the same time (e.g. FPR with DH or HU); the student picks theirs.
    var alternatives: [TimetableBlock] = []
    /// Homework is due in this lesson.
    var hasHomework = false
    /// No subject: a workshop, excursion or school event; the title is WebUntis' text.
    var isEvent = false

    /// Untis shows a changed room in green, independent of other changes (e.g. an exam in another room).
    var roomChanged: Bool { originalRoom != nil }
    /// A Vertretung: the teacher changed.
    var teacherChanged: Bool { kind == .substitution && !isEvent }
}

extension AppModel {
    /// Blocks for one day: double periods merged per course, parallel groups
    /// folded into one block, exams from the WebUntis exam list, overlaps in lanes.
    func timetableBlocks(on date: Date) -> [TimetableBlock] {
        let day = calendar.startOfDay(for: date)
        var blocks: [TimetableBlock]
        if let untis = data.untisTimetable, untisCovers(day, untis) {
            let exams = (data.untisExtras?.exams ?? []).filter { calendar.isDate($0.date, inSameDayAs: day) }
            blocks = untis.periods
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .map { block(from: $0, exams: exams) }
        } else {
            // Every parallel course, so `pickCourses` can offer the hidden ones as alternatives.
            let all = MeldeEngine.timetable(data, calendar: calendar, allCourses: true)
            let occurrences = (try? timetableOccurrencesOn(timetable: all, date: FfiDate(day, calendar: calendar))) ?? []
            blocks = occurrences.map { o in
                let subject = subject(for: o)
                let lesson = UUID(uuidString: o.lessonId)
                return TimetableBlock(
                    id: "lesson-\(o.lessonId)-\(o.startMinute)",
                    date: day,
                    startMinute: Int(o.startMinute),
                    endMinute: Int(o.endMinute),
                    shortTitle: subject?.displayShortName ?? "?",
                    subjectName: subject?.name ?? L("Unbekanntes Fach"),
                    teacher: subject?.teacher ?? "",
                    room: o.room,
                    kind: o.cancelled ? .cancelled : (o.substituted ? .substitution : .regular),
                    subjectID: subject?.id,
                    lessonID: lesson
                )
            }
        }
        // Homework due on this day in a subject marks that subject's lessons.
        let homeworkSubjects = Set(data.tasks.filter {
            $0.kind == .homework && !$0.isDone && ($0.dueDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false)
        }.compactMap(\.subjectID))
        for i in blocks.indices {
            if let id = blocks[i].subjectID, homeworkSubjects.contains(id) { blocks[i].hasHomework = true }
        }
        blocks.sort { ($0.startMinute, $0.endMinute) < ($1.startMinute, $1.endMinute) }
        return assignLanes(pickCourses(mergeDoublePeriods(blocks)))
    }

    /// Key for a parallel group in its weekly slot: subject and teacher, because
    /// groups often share the subject (FPR with DH, FPR with HU).
    func courseKey(_ block: TimetableBlock) -> String {
        "\(calendar.mondayIndex(of: block.date))|\(block.startMinute)|\(block.subjectName)|\(block.teacher)"
    }

    /// The student attends `chosen`; the other groups in that slot are hidden every week.
    func chooseCourse(_ chosen: TimetableBlock, among options: [TimetableBlock]) {
        let show = courseKey(chosen)
        let hide = options.map(courseKey).filter { $0 != show }
        mutate { data in
            var keys = Set(data.preferences.hiddenCourses)
            keys.formUnion(hide)
            keys.remove(show)
            data.preferences.hiddenCourses = keys.sorted()
        }
    }

    /// Lessons that start and end together are parallel groups (Kurse, split
    /// classes): one block shows the student's group, the others are a tap
    /// away, like WebUntis. Cancellations and substitutions stay visible side
    /// by side so no change is hidden.
    private func pickCourses(_ blocks: [TimetableBlock]) -> [TimetableBlock] {
        let hidden = Set(data.preferences.hiddenCourses)
        var result: [TimetableBlock] = []
        var used = Set<String>()
        for block in blocks where !used.contains(block.id) {
            let group = blocks.filter {
                !used.contains($0.id) && $0.startMinute == block.startMinute && $0.endMinute == block.endMinute
            }
            let foldable = group.count > 1 && group.allSatisfy { $0.kind != .cancelled && $0.kind != .substitution }
            guard foldable else {
                result.append(block)
                used.insert(block.id)
                continue
            }
            // Without a choice yet, an exam is shown first so it can't hide behind the count.
            // Courses chosen from Melden are hidden without a teacher ("weekday|start|subject|").
            let visible = group.filter { block in
                let key = courseKey(block)
                let withoutTeacher = key.split(separator: "|", omittingEmptySubsequences: false).prefix(3).joined(separator: "|") + "|"
                return !hidden.contains(key) && !hidden.contains(withoutTeacher)
            }
            var pick = visible.first { $0.kind == .exam } ?? visible.first ?? group[0]
            pick.alternatives = group.filter { $0.id != pick.id }
            result.append(pick)
            used.formUnion(group.map(\.id))
        }
        return result
    }

    /// Saturday school: own lessons or WebUntis periods on a Saturday.
    var hasSaturdayLessons: Bool {
        data.lessons.contains { $0.weekday == 5 }
            || (data.untisTimetable?.periods.contains { calendar.mondayIndex(of: $0.date) == 5 } ?? false)
    }

    /// Whether WebUntis data covers `day` (school look-ahead limits end earlier).
    private func untisCovers(_ day: Date, _ untis: UntisTimetable) -> Bool {
        calendar.startOfDay(for: untis.firstDay) <= day && day <= calendar.startOfDay(for: untis.lastDay)
    }

    /// The last day the school lets the student see, when WebUntis is connected.
    var untisVisibleUntil: Date? {
        guard data.untis != nil, let untis = data.untisTimetable else { return nil }
        return calendar.startOfDay(for: untis.lastDay)
    }

    /// The bell schedule: from WebUntis, or the student's own lesson times.
    var bellSchedule: [BellPeriod] {
        if let bells = data.untisTimetable?.bells, !bells.isEmpty { return bells }
        var seen = Set<[Int]>()
        let slots = data.lessons
            .map { [$0.startMinute, $0.endMinute] }
            .filter { seen.insert($0).inserted }
            .sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
        return slots.enumerated().map { BellPeriod(name: "\($0.offset + 1)", startMinute: $0.element[0], endMinute: $0.element[1]) }
    }

    /// An exam is either marked in the timetable or listed in WebUntis' exam
    /// list for the same day, time and subject (many schools only do the latter).
    private func block(from p: UntisPeriodRecord, exams: [UntisExamRecord]) -> TimetableBlock {
        let subject = data.subjects.first { $0.untisKey == p.subjectKey }
        let names = [p.subjectShort, p.subjectLong, p.subjectKey].filter { !$0.isEmpty }
        let listed = exams.contains { e in
            let sameTime = e.startMinute < p.endMinute && p.startMinute < e.endMinute
            let sameSubject = e.subject.isEmpty || names.contains { $0.caseInsensitiveCompare(e.subject) == .orderedSame }
            return sameTime && sameSubject
        }
        let kind: TimetableBlock.Kind =
            p.cancelled ? .cancelled
            : (p.exam || listed) ? .exam
            : p.irregular ? .substitution
            : p.originalRoom != nil ? .roomChange
            : .regular
        // Events have no subject; WebUntis names them in the lesson text.
        let isEvent = p.subjectShort.isEmpty && p.subjectLong.isEmpty
        let eventTitle = p.info?.components(separatedBy: " · ").first ?? L("Veranstaltung")
        var block = TimetableBlock(
            id: "untis-\(p.id)",
            date: p.date,
            startMinute: p.startMinute,
            endMinute: p.endMinute,
            shortTitle: isEvent ? eventTitle : (p.subjectShort.isEmpty ? String(p.subjectLong.prefix(4)) : p.subjectShort),
            subjectName: isEvent ? eventTitle : (subject?.name ?? (p.subjectLong.isEmpty ? p.subjectShort : p.subjectLong)),
            teacher: p.teacher,
            room: p.room,
            originalRoom: p.originalRoom,
            kind: kind,
            info: isEvent && p.info == eventTitle ? nil : p.info,
            subjectID: subject?.id
        )
        block.isEvent = isEvent
        return block
    }

    /// Joins back-to-back periods of the same course (as Untis draws them),
    /// also when parallel groups are interleaved in time order.
    private func mergeDoublePeriods(_ blocks: [TimetableBlock]) -> [TimetableBlock] {
        var merged: [TimetableBlock] = []
        for block in blocks {
            if let i = merged.lastIndex(where: { last in
                last.subjectName == block.subjectName && last.teacher == block.teacher
                    && last.room == block.room && last.kind == block.kind && last.info == block.info
                    && block.startMinute >= last.endMinute && block.startMinute - last.endMinute <= 25
            }) {
                merged[i].endMinute = block.endMinute
                merged[i].hasHomework = merged[i].hasHomework || block.hasHomework
            } else {
                merged.append(block)
            }
        }
        return merged.sorted { ($0.startMinute, $0.endMinute) < ($1.startMinute, $1.endMinute) }
    }

    /// Overlapping blocks share the column width.
    private func assignLanes(_ blocks: [TimetableBlock]) -> [TimetableBlock] {
        var result = blocks
        var laneEnds: [Int] = []
        for i in result.indices {
            if let free = laneEnds.firstIndex(where: { $0 <= result[i].startMinute }) {
                result[i].lane = free
                laneEnds[free] = result[i].endMinute
            } else {
                result[i].lane = laneEnds.count
                laneEnds.append(result[i].endMinute)
            }
        }
        for i in result.indices {
            let overlapping = result.filter { $0.startMinute < result[i].endMinute && result[i].startMinute < $0.endMinute }
            result[i].lanes = (overlapping.map(\.lane).max() ?? 0) + 1
            result[i].widthShare = 1 / Double(result[i].lanes)
            result[i].xShare = Double(result[i].lane) * result[i].widthShare
            // Like WebUntis: what takes place gets the room, cancelled lessons a narrow strip.
            let active = Set(overlapping.filter { $0.kind != .cancelled }.map(\.lane)).sorted()
            let cancelledOnly = Set(overlapping.filter { $0.kind == .cancelled }.map(\.lane)).subtracting(active).sorted()
            guard !active.isEmpty, !cancelledOnly.isEmpty else { continue }
            let activeShare = 0.72
            if let index = cancelledOnly.firstIndex(of: result[i].lane) {
                result[i].widthShare = (1 - activeShare) / Double(cancelledOnly.count)
                result[i].xShare = activeShare + Double(index) * result[i].widthShare
            } else if let index = active.firstIndex(of: result[i].lane) {
                result[i].widthShare = activeShare / Double(active.count)
                result[i].xShare = Double(index) * result[i].widthShare
            }
        }
        return result
    }
}
