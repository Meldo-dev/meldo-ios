import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Notenrechner: averages per subject and overall from the student's own
/// grades. An estimate; official grades come only from the school.
struct GradesView: View {
    @Environment(AppModel.self) private var model
    @State private var settings = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    Text(L("Geschätzter Schnitt"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let overall = model.overallGradeAverage {
                        Text(model.gradeText(overall))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } else {
                        Text(L("Noch keine Noten"))
                            .font(.title2.weight(.semibold))
                    }
                }
                .padding(.vertical, DS.spacingXS)
            } footer: {
                Text(L("Deine eigene Rechnung aus den Noten, die du einträgst. Die Zeugnisnote legt deine Schule fest."))
            }
            Section(L("Fächer")) {
                if model.subjects.isEmpty {
                    Text(L("Lege zuerst unter „Fächer“ deine Fächer an."))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.subjects) { subject in
                    NavigationLink { SubjectGradesView(subject: subject) } label: {
                        HStack(spacing: DS.spacingM) {
                            SubjectIcon(subject: subject, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(subject.name)
                                let count = model.grades(for: subject.id).count
                                Text(count == 0 ? L("Keine Noten") : L("\(count) Noten"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let grade = model.subjectGradeText(for: subject.id) {
                                Text(grade)
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Noten"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Notensystem"), systemImage: "slider.horizontal.3") { settings = true }
            }
        }
        .sheet(isPresented: $settings) { GradeSettingsView() }
    }
}

struct SubjectGradesView: View {
    @Environment(AppModel.self) private var model
    let subject: Subject
    @State private var editing: GradeEntry?
    @State private var adding = false
    @State private var target: Double = 2

    var body: some View {
        let summary = model.gradeSummary(for: subject.id)
        let points = model.preferences.gradeScale == .points
        List {
            Section {
                HStack {
                    stat(L("Note"), model.subjectGradeText(for: subject.id))
                    stat(L("Schnitt"), summary?.exact.map(model.gradeText))
                    stat(L("Schriftlich"), summary?.writtenAverage.map(model.gradeText))
                    stat(L("Mündlich"), summary?.oralAverage.map(model.gradeText))
                }
            }
            Section {
                Stepper(value: $target, in: points ? 0...15 : 1...6, step: 1) {
                    LabeledContent(L("Ziel"), value: model.gradeText(target))
                }
                if let forecast = model.gradeNeeded(for: subject.id, target: target) {
                    Text(forecastText(forecast))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L("Was brauche ich?"))
            } footer: {
                Text(L("Für die nächste schriftliche Note, mit deiner Gewichtung."))
            }
            Section(L("Noten")) {
                if model.grades(for: subject.id).isEmpty {
                    Text(L("Noch keine Noten")).foregroundStyle(.secondary)
                }
                ForEach(model.grades(for: subject.id)) { grade in
                    Button { editing = grade } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(grade.title.isEmpty ? (grade.written ? L("Schriftlich") : L("Mündlich")) : grade.title)
                                    .foregroundStyle(.primary)
                                Text(grade.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Localization.locale)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.singleGradeText(grade.value))
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }
                    // A row, not a link: keep the text neutral instead of the accent tint.
                    .tint(.primary)
                    .swipeActions {
                        Button(L("Löschen"), systemImage: "trash", role: .destructive) { model.deleteGrade(grade.id) }
                    }
                }
            }
        }
        .navigationTitle(subject.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Note hinzufügen"), systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { GradeEditorView(grade: nil, subjectID: subject.id) }
        .sheet(item: $editing) { GradeEditorView(grade: $0, subjectID: subject.id) }
        .onAppear { target = points ? 10 : 2 }
    }

    private func stat(_ label: String, _ text: String?) -> some View {
        VStack(spacing: 2) {
            Text(text ?? L("Keine"))
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func forecastText(_ forecast: FfiForecast) -> String {
        switch forecast.outcome {
        case .alreadySecured:
            return L("Das Ziel hast du sicher, egal wie die nächste Arbeit läuft.")
        case .reachable(let required):
            let grade = model.gradeText(required)
            // "or better" reads right on both scales (1–6 lower is better, 0–15 higher).
            return L("Du brauchst \(grade) oder besser.")
        case .unreachable(let best):
            let grade = model.gradeText(best)
            return L("Mit einer Arbeit nicht erreichbar. Bestenfalls \(grade).")
        }
    }
}

/// Add or edit a grade: 1–6 with tendency, or 0–15 points.
struct GradeEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let grade: GradeEntry?
    let subjectID: UUID

    @State private var written = true
    @State private var whole = 2
    @State private var tendency = 0
    @State private var points = 10
    @State private var weight = 1.0
    @State private var title = ""
    @State private var date = Date.now

    private var usesPoints: Bool { model.preferences.gradeScale == .points }

    var body: some View {
        NavigationStack {
            Form {
                Picker(L("Art"), selection: $written) {
                    Text(L("Schriftlich")).tag(true)
                    Text(L("Mündlich")).tag(false)
                }
                .pickerStyle(.segmented)
                Section(L("Note")) {
                    if usesPoints {
                        Stepper(value: $points, in: 0...15) {
                            LabeledContent(L("Punkte"), value: "\(points)")
                        }
                    } else {
                        Picker(L("Note"), selection: $whole) {
                            ForEach(1...6, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker(L("Tendenz"), selection: $tendency) {
                            Text(verbatim: "\(whole)+").tag(1)
                            Text(verbatim: "\(whole)").tag(0)
                            Text(verbatim: "\(whole)−").tag(-1)
                        }
                        .pickerStyle(.segmented)
                        LabeledContent(L("Wert"), value: model.gradeText(value))
                    }
                }
                Section {
                    TextField(L("Titel, z. B. 1. Klausur"), text: $title)
                    DatePicker(L("Datum"), selection: $date, displayedComponents: .date)
                    Stepper(value: $weight, in: 0.5...3, step: 0.5) {
                        LabeledContent(L("Gewicht"), value: weight.formatted(.number.precision(.fractionLength(1))))
                    }
                }
                if let grade {
                    Section {
                        Button(L("Note löschen"), role: .destructive) {
                            model.deleteGrade(grade.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(grade == nil ? L("Neue Note") : L("Note bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern")) {
                        model.saveGrade(GradeEntry(
                            id: grade?.id ?? UUID(), subjectID: subjectID, value: value,
                            written: written, weight: weight, title: title, date: date
                        ))
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    /// The tendency step comes from the settings (e.g. 2+ = 1.67 with 0.33).
    private var value: Double {
        if usesPoints { return Double(points) }
        let t: FfiTendency = tendency > 0 ? .plus : (tendency < 0 ? .minus : .none)
        return (try? gradeTraditionalValue(grade: UInt8(whole), tendency: t, step: model.preferences.tendencyStep)) ?? Double(whole)
    }

    private func load() {
        guard let grade else { return }
        written = grade.written
        weight = grade.weight
        title = grade.title
        date = grade.date
        if usesPoints {
            points = Int(grade.value.rounded())
        } else {
            whole = min(max(Int(grade.value.rounded()), 1), 6)
            let diff = grade.value - Double(whole)
            tendency = diff < -0.01 ? 1 : (diff > 0.01 ? -1 : 0)
        }
    }
}

struct GradeSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Notensystem"), selection: Binding(get: { model.preferences.gradeScale }, set: { model.setGradeScale($0) })) {
                        Text(L("Noten 1–6")).tag(GradeScaleChoice.traditional)
                        Text(L("Punkte 0–15")).tag(GradeScaleChoice.points)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L("Notensystem"))
                }
                Section {
                    let written = Int((model.preferences.writtenWeight * 100).rounded())
                    LabeledContent(L("Schriftlich"), value: "\(written) %")
                    Slider(
                        value: Binding(get: { model.preferences.writtenWeight }, set: { model.setWrittenWeight(($0 * 20).rounded() / 20) }),
                        in: 0...1
                    )
                    LabeledContent(L("Mündlich"), value: "\(100 - written) %")
                } header: {
                    Text(L("Gewichtung"))
                } footer: {
                    Text(L("Frag deine Lehrkraft, wie sie schriftlich und mündlich gewichtet."))
                }
                if model.preferences.gradeScale == .traditional {
                    Section {
                        Picker(L("Plus und Minus"), selection: Binding(get: { model.preferences.tendencyStep }, set: { model.setTendencyStep($0) })) {
                            Text(verbatim: "0,25").tag(0.25)
                            Text(verbatim: "0,33").tag(0.33)
                            Text(verbatim: "0,5").tag(0.5)
                        }
                    } footer: {
                        Text(L("So viel zählt ein Plus oder Minus, z. B. 2− = 2,33."))
                    }
                }
            }
            .navigationTitle(L("Notensystem"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig")) { dismiss() }
                }
            }
        }
    }
}
