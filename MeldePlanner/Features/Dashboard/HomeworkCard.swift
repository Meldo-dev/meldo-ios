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
