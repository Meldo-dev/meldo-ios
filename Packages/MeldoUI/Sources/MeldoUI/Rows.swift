import MeldeCore
import MeldoKit
import MeldoState
import SwiftUI

/// One task with a check circle. Checking off gives haptic feedback.
public struct TaskRow: View {
    @Environment(AppModel.self) private var model
    public let task: SchoolTask
    public let today: Date
    public var onOpen: () -> Void

    public init(task: SchoolTask, today: Date, onOpen: @escaping () -> Void) {
        self.task = task
        self.today = today
        self.onOpen = onOpen
    }

    @State private var checks = 0

    public var body: some View {
        let subject = model.subject(task.subjectID)
        HStack(spacing: DS.spacingM) {
            Button {
                checks += 1
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? Color.green : (subject?.color.color ?? Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? L("Als offen markieren") : L("Als erledigt markieren"))
            .sensoryFeedback(.success, trigger: checks) { _, _ in model.preferences.haptics }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .strikethrough(task.isDone)
                    HStack(spacing: DS.spacingS) {
                        if let subject {
                            Text(subject.name).foregroundStyle(subject.color.color)
                        }
                        if let due = task.dueDate {
                            Text(DueText.label(due, today: today, calendar: model.calendar))
                                .foregroundStyle(!task.isDone && due < model.calendar.startOfDay(for: today) ? Color.red : Color.secondary)
                        }
                        if task.recurrence != .never {
                            Image(systemName: "repeat").accessibilityLabel(L("Wiederholt sich"))
                        }
                        if task.reminderAt != nil, !task.isDone {
                            Image(systemName: "bell").accessibilityLabel(L("Erinnerung"))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if task.priority == .high, !task.isDone {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(L("Wichtig"))
            }
        }
    }
}

public enum DueText: Sendable {
    public static func label(_ due: Date, today: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return L("heute")
        case 1: return L("morgen")
        case -1: return L("gestern")
        case 2...6: return due.formatted(.dateTime.weekday(.wide).locale(Localization.locale))
        default: return due.formatted(.dateTime.day().month(.abbreviated).locale(Localization.locale))
        }
    }
}

/// One lesson in a list, colored like the timetable.
public struct BlockRow: View {
    @Environment(AppModel.self) private var model
    public let block: TimetableBlock
    public var isCurrent = false
    public var compact = false
    public var showInfo = false

    public init(block: TimetableBlock, isCurrent: Bool = false, compact: Bool = false, showInfo: Bool = false) {
        self.block = block
        self.isCurrent = isCurrent
        self.compact = compact
        self.showInfo = showInfo
    }

    public var body: some View {
        let subjectColor = model.subject(block.subjectID)?.color.color ?? .gray
        let style = BlockStyle(kind: block.kind, subjectColor: subjectColor)
        HStack(spacing: DS.spacingS) {
            // Lists show the subject's own color so lessons scan at a glance; the
            // grid keeps the WebUntis slate. Changes keep their change color.
            RoundedRectangle(cornerRadius: 2).fill(block.kind == .regular ? subjectColor : style.stripe).frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.subjectName)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(block.kind == .cancelled)
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                if showInfo, let info = block.info {
                    Text(info).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                Badge(text: L("Jetzt"), color: .accentColor)
            } else if let label = BlockStyle.label(for: block.kind), !compact {
                Badge(text: label, color: style.accent)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [TimeText.range(block.startMinute, block.endMinute)]
        if let room = block.room { parts.append(room) }
        if !compact, !block.teacher.isEmpty { parts.append(block.teacher) }
        return parts.joined(separator: " · ")
    }
}

public struct UntisExamRow: View {
    @Environment(AppModel.self) private var model
    public let exam: UntisExamRecord
    public let now: Date
    public var compact = false

    public init(exam: UntisExamRecord, now: Date, compact: Bool = false) {
        self.exam = exam
        self.now = now
        self.compact = compact
    }

    public var body: some View {
        let days = model.calendar.dateComponents([.day], from: model.calendar.startOfDay(for: now), to: exam.date).day ?? 0
        HStack(spacing: DS.spacingS) {
            RoundedRectangle(cornerRadius: 2).fill(Color.yellow).frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(exam.name.isEmpty ? exam.subject : "\(exam.subject) · \(exam.name)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(exam.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Localization.locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !compact, !exam.rooms.isEmpty {
                    Text(exam.rooms.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Badge(text: days == 0 ? L("heute") : (days == 1 ? L("morgen") : L("in \(days) Tagen")), color: .orange)
        }
        .accessibilityElement(children: .combine)
    }
}

public struct AbsenceRow: View {
    @Environment(AppModel.self) private var model
    public let absence: UntisAbsenceRecord

    public init(absence: UntisAbsenceRecord) {
        self.absence = absence
    }

    public var body: some View {
        row
    }

    private var row: some View {
        HStack(alignment: .top, spacing: DS.spacingM) {
            Image(systemName: absence.excused ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(absence.excused ? Color.green : Color.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(dates)
                    .font(.subheadline.weight(.semibold))
                if let late = model.lateMinutes(absence) {
                    Text("\(Image(systemName: "clock.badge.exclamationmark")) \(L("Verspätung · \(late) Min."))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(TimeText.range(absence.startMinute, absence.endMinute))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if !absence.reason.isEmpty {
                    Text(absence.reason).font(.caption).foregroundStyle(.secondary)
                }
                if !absence.text.isEmpty {
                    Text(absence.text).font(.caption).foregroundStyle(.secondary)
                }
                Text(absence.excused ? L("entschuldigt") : L("nicht entschuldigt"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(absence.excused ? Color.green : Color.red)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dates: String {
        let style = Date.FormatStyle(locale: Localization.locale).weekday(.abbreviated).day().month(.abbreviated)
        if Calendar.current.isDate(absence.firstDay, inSameDayAs: absence.lastDay) {
            return absence.firstDay.formatted(style)
        }
        return "\(absence.firstDay.formatted(style))–\(absence.lastDay.formatted(style))"
    }
}
