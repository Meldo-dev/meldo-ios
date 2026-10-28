import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

struct UpcomingExamsCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize

    var body: some View {
        let exams = model.upcomingUntisExams(from: now)
        Card(title: L("Prüfungen"), systemImage: "pencil.and.list.clipboard") {
            if exams.isEmpty {
                Text(model.data.untis == nil
                     ? L("Verbinde WebUntis, dann erscheinen hier deine Prüfungstermine.")
                     : L("Keine Prüfungen eingetragen."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let limit = size == .small ? 1 : (size == .medium ? 3 : 8)
                VStack(alignment: .leading, spacing: DS.spacingS) {
                    ForEach(exams.prefix(limit)) { exam in
                        UntisExamRow(exam: exam, now: now, compact: size == .small)
                    }
                }
            }
        }
    }
}

struct SchoolNewsCard: View {
    @Environment(AppModel.self) private var model
    var size: CardSize

    var body: some View {
        let news = model.data.untisExtras?.news ?? []
        Card(title: L("Nachrichten"), systemImage: "megaphone") {
            if news.isEmpty {
                Text(model.data.untis == nil
                     ? L("Verbinde WebUntis, um Nachrichten deiner Schule zu sehen.")
                     : L("Heute keine Nachrichten von der Schule."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(news.prefix(size == .large ? 6 : (size == .medium ? 2 : 1))) { message in
                    VStack(alignment: .leading, spacing: 2) {
                        if !message.subject.isEmpty {
                            Text(message.subject).font(.subheadline.weight(.semibold))
                        }
                        if size != .small {
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(size == .large ? nil : 3)
                        }
                    }
                }
            }
        }
    }
}

struct AbsencesCard: View {
    @Environment(AppModel.self) private var model
    var size: CardSize

    var body: some View {
        let absences = model.data.untisExtras?.absences ?? []
        let open = absences.filter { !$0.excused }.count
        Card(title: L("Abwesenheiten"), systemImage: "person.crop.circle.badge.clock") {
            if model.data.untis == nil {
                Text(L("Verbinde WebUntis, um deine Fehlzeiten zu sehen."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DS.spacingS) {
                    Text(absences.count, format: .number)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text(L("in diesem Schuljahr"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if open > 0 {
                    Label(L("\(open) nicht entschuldigt"), systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                NavigationLink(L("Alle")) { AbsencesView() }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}
