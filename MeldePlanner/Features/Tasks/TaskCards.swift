import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// Homework due soon, check-off in place, and the homework streak.
struct HomeworkCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize = .medium
    @State private var adding = false

    var body: some View {
        let upcoming = model.upcomingHomework(today: now, limit: size == .large ? 8 : 3)
        let streak = model.homeworkStreak(asOf: now)
        Card(title: L("Hausaufgaben"), systemImage: "book") {
            if size == .small {
                HStack(alignment: .firstTextBaseline, spacing: DS.spacingS) {
                    Text(upcoming.count, format: .number)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text(L("bald fällig"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                NavigationLink(L("Alle")) { TaskListView() }
                    .font(.subheadline.weight(.semibold))
            } else if upcoming.isEmpty {
                Text(L("Für heute und morgen ist alles erledigt."))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcoming) { task in
                        TaskRow(task: task, today: now) {}
                    }
                }
            }
            if size != .small {
                HStack {
                    // A zero streak only discourages; it appears once there is one.
                    if streak > 0 {
                        Label(L("\(streak) Tage pünktlich in Folge"), systemImage: "flame")
                            .foregroundStyle(Color.orange)
                            .font(.subheadline)
                    }
                    Spacer()
                    NavigationLink(L("Alle")) { TaskListView() }
                        .font(.subheadline.weight(.semibold))
                }
                Button(L("Hausaufgabe eintragen"), systemImage: "plus") { adding = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .sheet(isPresented: $adding) { TaskEditorView(task: nil, kind: .homework) }
    }
}

/// Open to-dos (not homework), check off in place.
struct TodosCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    var size: CardSize
    @State private var adding = false

    var body: some View {
        let open = model.tasks.filter { $0.kind == .todo && !$0.isDone }
        Card(title: L("To-dos"), systemImage: "checklist") {
            if open.isEmpty {
                Text(L("Nichts zu tun"))
                    .foregroundStyle(.secondary)
            } else if size == .small {
                HStack(alignment: .firstTextBaseline, spacing: DS.spacingS) {
                    Text(open.count, format: .number)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text(L("offen")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(open.prefix(size == .large ? 8 : 3)) { task in
                        TaskRow(task: task, today: now) {}
                    }
                }
            }
            if size != .small {
                Button(L("To-do hinzufügen"), systemImage: "plus") { adding = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .sheet(isPresented: $adding) { TaskEditorView(task: nil, kind: .todo) }
    }
}
