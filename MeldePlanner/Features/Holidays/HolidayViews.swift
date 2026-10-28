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
