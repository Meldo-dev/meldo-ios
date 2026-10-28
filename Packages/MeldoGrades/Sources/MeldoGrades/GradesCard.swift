import Charts
import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Estimated average from the student's own grades (Notenrechner).
struct GradesCard: View {
    @Environment(AppModel.self) private var model
    var size: CardSize

    var body: some View {
        Card(title: L("Notenschnitt"), systemImage: "graduationcap") {
            if let overall = model.overallGradeAverage {
                Text(model.gradeText(overall))
                    .font(.system(size: size == .small ? 34 : 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(L("geschätzt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if size != .small {
                    let graded = model.subjects.compactMap { subject in
                        model.subjectGradeText(for: subject.id).map { (subject, $0) }
                    }
                    ForEach(graded.prefix(size == .large ? 8 : 3), id: \.0.id) { subject, grade in
                        HStack {
                            Text(subject.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(grade).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
            } else {
                Text(L("Trag deine Noten ein, dann rechnet Meldo deinen Schnitt aus."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            NavigationLink(L("Notenrechner")) { GradesView() }
                .font(.subheadline.weight(.semibold))
        }
    }
}
