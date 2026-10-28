import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Aufgaben: Hausaufgaben and to-dos, with their Start cards and the task editor.
    public static var tasks: MeldoFeature {
        var feature = MeldoFeature(id: "tasks", title: { L("Aufgaben") }, symbol: "checklist", placement: .bar) {
            TaskListView()
        }
        feature.dashboardCards = [
            DashboardCardProvider(.homework, title: { L("Hausaufgaben") }, symbol: "book") { HomeworkCard(now: $0, size: $1) },
            DashboardCardProvider(.todos, title: { L("To-dos") }, symbol: "checklist") { TodosCard(now: $0, size: $1) },
        ]
        feature.destination = { route in
            guard case .newTask(let kind, let subjectID) = route else { return nil }
            return AnyView(TaskEditorView(task: nil, kind: kind, subjectID: subjectID))
        }
        return feature
    }
}
