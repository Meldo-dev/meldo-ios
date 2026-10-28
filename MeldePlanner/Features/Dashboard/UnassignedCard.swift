import SwiftUI

/// Meldungen logged from the Lock Screen or Control Center outside a lesson
/// have no subject yet; one tap assigns them all.
struct UnassignedCard: View {
    @Environment(AppModel.self) private var model
    var now: Date
    @State private var assigning = false

    var body: some View {
        let unassigned = model.unassignedEntries(on: now)
        if !unassigned.isEmpty {
            Card(title: L("Ohne Fach"), systemImage: "questionmark.circle") {
                Text(unassigned.count == 1
                     ? L("1 Meldung von heute hat noch kein Fach.")
                     : L("\(unassigned.count) Meldungen von heute haben noch kein Fach."))
                    .foregroundStyle(.secondary)
                Button(L("Fach zuordnen")) { assigning = true }
                    .buttonStyle(.glassProminent)
            }
            .sheet(isPresented: $assigning) {
                SubjectPickerSheet { subjectID in
                    for entry in unassigned { model.reassignParticipation(entry.id, to: subjectID) }
                }
            }
        }
    }
}
