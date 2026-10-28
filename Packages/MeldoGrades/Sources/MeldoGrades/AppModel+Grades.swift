import Foundation
import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI

/// Notenrechner: the student's own grades, averaged by the Rust core with the
/// configured scale and weights. Estimates only; official grades come from
/// the school. Participation counts (Meldungen) are never mixed in.
extension AppModel {
    var gradeConfig: FfiGradingConfig {
        let p = data.preferences
        return FfiGradingConfig(
            scale: p.gradeScale == .points ? .points : .traditional,
            writtenWeight: p.writtenWeight,
            oralWeight: 1 - p.writtenWeight,
            rounding: .halfTowardBetter
        )
    }

    func grades(for subjectID: UUID) -> [GradeEntry] {
        data.grades.filter { $0.subjectID == subjectID }.sorted { $0.date > $1.date }
    }

    private func assessments(_ grades: [GradeEntry]) -> [FfiAssessment] {
        grades.map { FfiAssessment(value: $0.value, weight: $0.weight, category: $0.written ? .written : .oral) }
    }

    func gradeSummary(for subjectID: UUID) -> FfiSubjectSummary? {
        let list = grades(for: subjectID)
        guard !list.isEmpty else { return nil }
        return try? gradeSubjectSummary(config: gradeConfig, assessments: assessments(list))
    }

    /// Average over all subjects with grades, each subject weighted equally.
    var overallGradeAverage: Double? {
        let weights = data.subjects.compactMap { subject -> FfiSubjectWeight? in
            guard let exact = gradeSummary(for: subject.id)?.exact else { return nil }
            return FfiSubjectWeight(average: exact, weight: 1)
        }
        return gradeOverallAverage(subjects: weights)
    }

    /// What the next written grade must be to reach `target` (e.g. 2.0 or 11 points).
    func gradeNeeded(for subjectID: UUID, target: Double) -> FfiForecast? {
        try? gradeForecast(
            config: gradeConfig,
            existing: assessments(grades(for: subjectID)),
            planned: [FfiPlannedAssessment(weight: 1, category: .written)],
            targetGrade: target
        )
    }

    func saveGrade(_ grade: GradeEntry) {
        mutate { data in
            if let i = data.grades.firstIndex(where: { $0.id == grade.id }) {
                data.grades[i] = grade
            } else {
                data.grades.append(grade)
            }
        }
    }

    func deleteGrade(_ id: UUID) {
        mutate { $0.grades.removeAll { $0.id == id } }
    }

    /// Grades are stored without their scale, so switching converts every grade
    /// (KMK table in Rust); otherwise 11 points would be read as an invalid 1–6 grade.
    func setGradeScale(_ scale: GradeScaleChoice) {
        mutate { data in
            let old = data.preferences.gradeScale
            guard old != scale else { return }
            let step = data.preferences.tendencyStep
            for i in data.grades.indices {
                data.grades[i].value = Self.convert(data.grades[i].value, from: old, step: step)
            }
            data.preferences.gradeScale = scale
        }
    }

    private nonisolated static func convert(_ value: Double, from old: GradeScaleChoice, step: Double) -> Double {
        switch old {
        case .points:
            let points = UInt8(min(max(value.rounded(), 0), 15))
            guard let grade = try? gradePointsToTraditional(points: points) else { return value }
            return (try? gradeTraditionalValue(grade: grade.grade, tendency: grade.tendency, step: step)) ?? Double(grade.grade)
        case .traditional:
            let whole = min(max(Int(value.rounded()), 1), 6)
            let diff = value - Double(whole)
            let tendency: FfiTendency = diff < -0.01 ? .plus : (diff > 0.01 ? .minus : .none)
            return Double((try? gradeTraditionalToPoints(grade: UInt8(whole), tendency: tendency)) ?? 0)
        }
    }

    func setWrittenWeight(_ weight: Double) {
        mutate { $0.preferences.writtenWeight = min(max(weight, 0), 1) }
    }

    func setTendencyStep(_ step: Double) {
        mutate { $0.preferences.tendencyStep = step }
    }

    /// One grade as the teacher wrote it ("3−", "2+", "11 P."); averages keep `gradeText`.
    func singleGradeText(_ value: Double) -> String {
        if data.preferences.gradeScale == .points {
            return L("\(String(Int(value.rounded()))) P.")
        }
        return markText(value)
    }

    /// A subject's grade as a report card writes it: the nearest grade with
    /// tendency ("2−") or rounded points ("11 P."), from the Rust core. Still an
    /// estimate; the "Schnitt" next to it stays exact (`gradeText`).
    func subjectGradeText(for subjectID: UUID) -> String? {
        guard let summary = gradeSummary(for: subjectID) else { return nil }
        if data.preferences.gradeScale == .points {
            return summary.rounded.map { L("\(String(Int($0))) P.") }
        }
        return summary.exact.map(markText)
    }

    /// The 1–6 grade with tendency closest to `value`, with the configured step.
    private func markText(_ value: Double) -> String {
        guard let mark = try? gradeNearestTraditional(
            average: value, step: data.preferences.tendencyStep, rounding: gradeConfig.rounding
        ) else { return gradeText(value) }
        let sign = switch mark.tendency {
        case .plus: "+"
        case .none: ""
        case .minus: "\u{2212}"
        }
        return "\(mark.grade)\(sign)"
    }

    /// "2,33" or "11,0 P." in the student's scale: exact averages (Schnitt).
    func gradeText(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(data.preferences.gradeScale == .points ? 1 : 2)).locale(Localization.locale))
        return data.preferences.gradeScale == .points ? L("\(number) P.") : number
    }
}
