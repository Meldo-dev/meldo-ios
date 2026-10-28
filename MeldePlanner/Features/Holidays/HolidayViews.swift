import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Mehr → Ferien: the school's current and upcoming holidays. Past ones are left out,
/// so the list doesn't grow with every school year WebUntis keeps.
struct HolidayListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.calendar.startOfDay(for: model.currentDate)
        let upcoming = model.data.holidays
            .filter { model.calendar.startOfDay(for: $0.lastDay) >= today }
            .sorted { $0.firstDay < $1.firstDay }
        List {
            if model.data.holidays.isEmpty {
                ContentUnavailableView {
                    Label(L("Keine Ferien eingetragen"), systemImage: "sun.horizon")
                } description: {
                    Text(L("Verbinde WebUntis, dann erscheinen hier die Ferien deiner Schule. In den Ferien fragt Meldo nicht nach Meldungen."))
                }
            } else if upcoming.isEmpty {
                ContentUnavailableView {
                    Label(L("Keine kommenden Ferien"), systemImage: "sun.horizon")
                } description: {
                    Text(L("Die nächsten Ferien erscheinen hier, sobald deine Schule sie in WebUntis einträgt."))
                }
            } else {
                Section {
                    ForEach(upcoming) { holiday in
                        let now = model.holiday(on: today)?.id == holiday.id
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(holiday.name).font(.body.weight(.semibold))
                                Text(HolidayText.range(holiday))
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if now { Badge(text: L("Jetzt"), color: .meldoOrange) }
                        }
                    }
                } footer: {
                    Text(L("In den Ferien fallen alle Stunden aus und Meldo fragt nicht nach Meldungen."))
                }
            }
        }
        .navigationTitle(L("Ferien"))
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
