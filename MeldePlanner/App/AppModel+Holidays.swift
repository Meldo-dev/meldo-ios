import Foundation

/// Holidays (Ferien), imported from WebUntis. Lessons on these days are already
/// skipped by the Rust schedule; these helpers are for showing them.
extension AppModel {
    /// The holiday that includes `date`, if any.
    func holiday(on date: Date) -> Holiday? {
        let day = calendar.startOfDay(for: date)
        return data.holidays.first {
            calendar.startOfDay(for: $0.firstDay) <= day && day <= calendar.startOfDay(for: $0.lastDay)
        }
    }

    /// A holiday that overlaps the week (Monday–Sunday) containing `date`.
    func holiday(inWeekOf date: Date) -> Holiday? {
        let monday = calendar.date(byAdding: .day, value: -calendar.mondayIndex(of: date), to: calendar.startOfDay(for: date)) ?? date
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        return data.holidays.first {
            calendar.startOfDay(for: $0.firstDay) <= sunday && monday <= calendar.startOfDay(for: $0.lastDay)
        }
    }

    /// Holidays that haven't ended yet, soonest first.
    func upcomingHolidays(from date: Date) -> [Holiday] {
        let day = calendar.startOfDay(for: date)
        return data.holidays
            .filter { calendar.startOfDay(for: $0.lastDay) >= day }
            .sorted { $0.firstDay < $1.firstDay }
    }
}

enum HolidayText {
    /// "19.10.–01.11.", or "06.05." for a single day (the locale's short day and month).
    static func range(_ holiday: Holiday) -> String {
        let style = Date.FormatStyle(locale: Localization.locale).day(.twoDigits).month(.twoDigits)
        if Calendar.current.isDate(holiday.firstDay, inSameDayAs: holiday.lastDay) {
            return holiday.firstDay.formatted(style)
        }
        return "\(holiday.firstDay.formatted(style))–\(holiday.lastDay.formatted(style))"
    }
}
