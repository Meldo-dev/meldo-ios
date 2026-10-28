import SwiftUI

/// Banner for the timetable and calendar: "Herbstferien · 19.10.–01.11.".
struct HolidayBanner: View {
    let holiday: Holiday

    var body: some View {
        HStack(spacing: DS.spacingM) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(holiday.name).font(.headline)
                Text(HolidayText.range(holiday))
                    .font(.subheadline)
                    .monospacedDigit()
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(DS.spacingM)
        // Blue like WebUntis, so holidays look the same everywhere.
        .background(Color.untisHoliday, in: .rect(cornerRadius: DS.rowRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

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
