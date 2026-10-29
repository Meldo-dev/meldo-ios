import Foundation
import MeldoKit

/// Lookups over the WebUntis extras (exams, absences) and Meldungen for the
/// Start cards and the Kalender.
extension AppModel {
    /// Exams from today on. Uses the WebUntis exam list; when a school hides
    /// it, the exam periods from the timetable stand in.
    public func upcomingUntisExams(from date: Date) -> [UntisExamRecord] {
        let today = calendar.startOfDay(for: date)
        let listed = (data.untisExtras?.exams ?? []).filter { $0.date >= today }
        if !listed.isEmpty { return listed.sorted { ($0.date, $0.startMinute) < ($1.date, $1.startMinute) } }
        return (data.untisTimetable?.periods ?? [])
            .filter { $0.exam && !$0.cancelled && $0.date >= today }
            .map { p in
                UntisExamRecord(
                    id: p.id, date: p.date, startMinute: p.startMinute, endMinute: p.endMinute,
                    subject: p.subjectShort.isEmpty ? p.subjectLong : p.subjectShort,
                    name: p.info ?? "", examType: "", teachers: p.teacher.isEmpty ? [] : [p.teacher],
                    rooms: p.room.map { [$0] } ?? [], text: ""
                )
            }
            .sorted { ($0.date, $0.startMinute) < ($1.date, $1.startMinute) }
    }

    public func untisExams(on date: Date) -> [UntisExamRecord] {
        upcomingUntisExams(from: .distantPast).filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    public func absences(on date: Date) -> [UntisAbsenceRecord] {
        let day = calendar.startOfDay(for: date)
        return (data.untisExtras?.absences ?? []).filter {
            calendar.startOfDay(for: $0.firstDay) <= day && day <= calendar.startOfDay(for: $0.lastDay)
        }
    }

    /// Days (local midnight) with at least one Meldung.
    public var meldungDays: Set<Date> {
        Set(data.participation.map { calendar.startOfDay(for: $0.recordedAt) })
    }

    /// Minutes late when an absence is a late arrival: one day, starting with that day's
    /// first lesson in the WebUntis timetable and over before that lesson ends.
    /// Days without WebUntis lessons stay unknown (nil), never guessed from a weekday.
    public func lateMinutes(_ absence: UntisAbsenceRecord) -> Int? {
        guard calendar.isDate(absence.firstDay, inSameDayAs: absence.lastDay),
              let periods = data.untisTimetable?.periods,
              let first = periods
                .filter({ !$0.cancelled && calendar.isDate($0.date, inSameDayAs: absence.firstDay) })
                .min(by: { $0.startMinute < $1.startMinute }),
              absence.startMinute == first.startMinute,
              absence.endMinute > absence.startMinute,
              absence.endMinute < first.endMinute
        else { return nil }
        // Minutes come from other devices too: a nonsense value gives no number, not a crash.
        let late = absence.endMinute.subtractingReportingOverflow(absence.startMinute)
        return late.overflow ? nil : late.partialValue
    }
}

