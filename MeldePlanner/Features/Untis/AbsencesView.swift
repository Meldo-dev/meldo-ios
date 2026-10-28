import SwiftUI

/// Absences from the WebUntis class register, newest first, with a summary.
struct AbsencesView: View {
    @Environment(AppModel.self) private var model
    @State private var onlyOpen = false

    var body: some View {
        let all = model.data.untisExtras?.absences ?? []
        let shown = onlyOpen ? all.filter { !$0.excused } : all
        List {
            if model.data.untis == nil {
                ContentUnavailableView {
                    Label(L("Abwesenheiten"), systemImage: "person.crop.circle.badge.clock")
                } description: {
                    Text(L("Verbinde WebUntis, um deine Fehlzeiten zu sehen."))
                } actions: {
                    NavigationLink(L("WebUntis verbinden")) { UntisConnectView() }
                        .buttonStyle(.glassProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    // One row, so the counts and the note share the card's full width.
                    VStack(spacing: DS.spacingM) {
                        HStack(spacing: 0) {
                            summary(all.count, L("gesamt"), .primary)
                            summary(all.filter(\.excused).count, L("entschuldigt"), .green)
                            summary(all.filter { !$0.excused }.count, L("offen"), .red)
                        }
                        // A few minutes late reads very differently from a missed day.
                        let late = all.filter { model.lateMinutes($0) != nil }.count
                        if late > 0 {
                            Text(L("Davon \(late) Verspätungen"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.spacingXS)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    Toggle(L("Nur nicht entschuldigte"), isOn: $onlyOpen)
                } footer: {
                    Text(L("Aus dem Klassenbuch in WebUntis, dieses Schuljahr. Entschuldigungen reichst du weiter bei deiner Schule ein."))
                }
                if shown.isEmpty {
                    Text(L("Keine Abwesenheiten."))
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(shown) { absence in
                            AbsenceRow(absence: absence)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Abwesenheiten"))
    }

    private func summary(_ count: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(count, format: .number)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct AbsenceRow: View {
    @Environment(AppModel.self) private var model
    let absence: UntisAbsenceRecord
    @State private var writingExcuse = false

    var body: some View {
        row
            .contextMenu {
                Button(L("Entschuldigung erstellen"), systemImage: "doc.text") { writingExcuse = true }
            }
            .sheet(isPresented: $writingExcuse) { ExcuseNoteView(absence: absence) }
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
