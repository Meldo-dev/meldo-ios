import SwiftUI

struct SubjectListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Subject?
    @State private var creating = false
    @State private var pendingDelete: Subject?

    var body: some View {
        List {
            if model.subjects.isEmpty {
                ContentUnavailableView {
                    Label(L("Noch keine Fächer"), systemImage: "books.vertical")
                } description: {
                    Text(L("Fächer bündeln Stunden, Meldungen und später deine Noten."))
                } actions: {
                    Button(L("Fach anlegen")) { creating = true }
                        .buttonStyle(.glassProminent)
                }
            }
            ForEach(model.subjects) { subject in
                Button { editing = subject } label: {
                    HStack(spacing: DS.spacingM) {
                        SubjectIcon(subject: subject)
                        VStack(alignment: .leading) {
                            Text(subject.name).foregroundStyle(.primary)
                            if !subject.teacher.isEmpty {
                                Text(subject.teacher).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .swipeActions {
                    Button(L("Löschen"), systemImage: "trash", role: .destructive) { pendingDelete = subject }
                }
            }
        }
        .navigationTitle(L("Fächer"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Fach anlegen"), systemImage: "plus") { creating = true }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(L("Fertig")) { dismiss() }
            }
        }
        .sheet(item: $editing) { SubjectEditorView(subject: $0) }
        .sheet(isPresented: $creating) { SubjectEditorView(subject: nil) }
        .confirmationDialog(
            L("Fach löschen?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { subject in
            Button(L("„\(subject.name)“ und seine Stunden löschen"), role: .destructive) {
                model.deleteSubject(subject.id)
            }
        } message: { _ in
            Text(L("Bisherige Meldungen bleiben erhalten, aber ohne Fach."))
        }
    }
}

struct SubjectEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let isNew: Bool
    @State private var draft: Subject

    init(subject: Subject?) {
        isNew = subject == nil
        _draft = State(initialValue: subject ?? Subject(name: ""))
    }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: DS.spacingM)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name, z. B. Mathematik"), text: $draft.name)
                        .textInputAutocapitalization(.words)
                    TextField(L("Kürzel, z. B. M"), text: $draft.shortName)
                    TextField(L("Lehrkraft (optional)"), text: $draft.teacher)
                }
                Section(L("Farbe")) {
                    LazyVGrid(columns: columns, spacing: DS.spacingM) {
                        ForEach(SubjectColor.allCases) { color in
                            Button { draft.color = color } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if draft.color == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.rawValue)
                            .accessibilityAddTraits(draft.color == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, DS.spacingXS)
                }
                Section(L("Symbol")) {
                    LazyVGrid(columns: columns, spacing: DS.spacingM) {
                        ForEach(DS.subjectSymbols, id: \.self) { symbol in
                            Button { draft.symbolName = symbol } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(draft.symbolName == symbol ? draft.color.color : .secondary)
                                    .background(
                                        draft.symbolName == symbol ? draft.color.color.opacity(0.16) : .clear,
                                        in: .rect(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                    .padding(.vertical, DS.spacingXS)
                }
            }
            .navigationTitle(isNew ? L("Neues Fach") : L("Fach bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern")) {
                        model.upsert(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
