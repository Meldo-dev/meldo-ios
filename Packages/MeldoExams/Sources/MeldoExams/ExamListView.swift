import MeldoKit
import MeldoState
import MeldoUI
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A scanned or imported PDF waiting for its details.
struct PendingExam: Identifiable {
    let id = UUID()
    let pdf: Data
    let pageCount: Int
}

/// Prüfungen & Scans, grouped by subject.
struct ExamListView: View {
    @Environment(AppModel.self) private var model
    @State private var scanning = false
    @State private var importing = false
    @State private var choosingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pending: PendingExam?
    @State private var problem: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad: the exam shown next to the list.
    @State private var selected: UUID?
    @State private var filter: DocumentCategory?

    private var groups: [(subject: Subject?, exams: [ExamDocument])] {
        let shown = model.exams.filter { filter == nil || $0.kind == filter }
        let bySubject = Dictionary(grouping: shown, by: \.subjectID)
        var result: [(subject: Subject?, exams: [ExamDocument])] = []
        for subject in model.subjects {
            if let exams = bySubject[subject.id] { result.append((subject: subject, exams: exams)) }
        }
        let orphans = shown.filter { exam in exam.subjectID.flatMap { model.subject($0) } == nil }
        if !orphans.isEmpty { result.append((subject: nil, exams: orphans)) }
        return result
    }

    var body: some View {
        if sizeClass == .regular, let shown = selected ?? model.exams.first?.id {
            // iPad: list and PDF side by side.
            HStack(spacing: 0) {
                examList.frame(width: 380)
                Divider()
                ExamDetailView(examID: shown)
                    .id(shown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            examList
        }
    }

    private var examList: some View {
        List {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            if !model.exams.isEmpty {
                Picker(L("Art"), selection: $filter) {
                    Text(L("Alle")).tag(DocumentCategory?.none)
                    ForEach(DocumentCategory.allCases) { Text(DocumentCategoryText.plural($0)).tag(DocumentCategory?.some($0)) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            let upcoming = model.upcomingUntisExams(from: model.currentDate)
            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { exam in
                        UntisExamRow(exam: exam, now: model.currentDate)
                    }
                } header: {
                    Text(L("Anstehend"))
                } footer: {
                    Text(L("Termine aus WebUntis. Zurückgegebene Arbeiten scannst du unten ein."))
                }
            }
            if model.exams.isEmpty {
                ExamsWelcome(
                    canScan: DocumentScanner.isSupported,
                    scan: { problem = nil; scanning = true },
                    photos: { problem = nil; choosingPhotos = true },
                    files: { problem = nil; importing = true }
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            ForEach(groups, id: \.subject?.id) { group in
                Section {
                    ForEach(group.exams) { exam in
                        Group {
                            if sizeClass == .regular {
                                Button { selected = exam.id } label: { ExamRow(exam: exam) }
                                    .buttonStyle(.plain)
                                    .listRowBackground((selected ?? model.exams.first?.id) == exam.id ? Color.accentColor.opacity(0.15) : nil)
                            } else {
                                NavigationLink { ExamDetailView(examID: exam.id) } label: {
                                    ExamRow(exam: exam)
                                }
                            }
                        }
                        .swipeActions {
                            Button(L("Löschen"), systemImage: "trash", role: .destructive) {
                                if selected == exam.id { selected = nil }
                                model.deleteExam(exam.id)
                            }
                        }
                    }
                } header: {
                    Label(group.subject?.name ?? L("Ohne Fach"), systemImage: group.subject?.symbolName ?? "questionmark.folder")
                }
            }
        }
        .navigationTitle(L("Dokumente"))
        .onAppear { model.organizeDocuments() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu(L("Hinzufügen"), systemImage: "plus") { actionButtons }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                if let pdf = ExamFiles.pdf(from: images) {
                    pending = PendingExam(pdf: pdf, pageCount: images.count)
                } else {
                    problem = L("Der Scan konnte nicht als PDF gespeichert werden.")
                }
            } onCancel: {
                scanning = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            importPDF(result)
        }
        .photosPicker(isPresented: $choosingPhotos, selection: $photoItems, maxSelectionCount: 30, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .sheet(item: $pending) { item in
            ExamEditorView(mode: .new(item))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if DocumentScanner.isSupported {
            Button(L("Scannen"), systemImage: "doc.viewfinder") { problem = nil; scanning = true }
        }
        Button(L("Aus Fotos"), systemImage: "photo.on.rectangle") { problem = nil; choosingPhotos = true }
        Button(L("PDF importieren"), systemImage: "square.and.arrow.down") { problem = nil; importing = true }
    }

    /// Photos of a returned Klausur become one PDF, in the order picked.
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        if let pdf = ExamFiles.pdf(from: images) {
            pending = PendingExam(pdf: pdf, pageCount: images.count)
        } else {
            problem = L("Die Fotos konnten nicht als PDF gespeichert werden.")
        }
    }

    private func importPDF(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Read at most one byte more than allowed, so a huge file is never loaded whole.
        let handle = try? FileHandle(forReadingFrom: url)
        defer { try? handle?.close() }
        let read = try? handle?.read(upToCount: ExamFiles.maxImportBytes + 1)
        guard (read?.count ?? 0) <= ExamFiles.maxImportBytes else {
            problem = L("Diese Datei ist zu groß (höchstens 100 MB).")
            return
        }
        guard let data = read ?? nil, let document = PDFDocument(data: data) else {
            problem = L("Diese Datei ist kein lesbares PDF.")
            return
        }
        pending = PendingExam(pdf: data, pageCount: document.pageCount)
    }
}

private struct ExamRow: View {
    let exam: ExamDocument

    var body: some View {
        HStack(spacing: DS.spacingM) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.title).font(.body.weight(.semibold))
                Text(L("\(exam.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Localization.locale))) · \(exam.pageCount) Seiten"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !exam.grade.isEmpty {
                Badge(text: exam.grade, color: .accentColor)
            }
        }
    }
}

struct ExamDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let examID: UUID
    @State private var editing = false

    var body: some View {
        if let exam = model.exams.first(where: { $0.id == examID }), let url = model.fileURL(for: exam) {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(exam.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(L("Details"), systemImage: "info.circle") { editing = true }
                    }
                }
                .sheet(isPresented: $editing) { ExamEditorView(mode: .existing(exam)) }
        } else {
            ContentUnavailableView(L("Prüfung nicht gefunden"), systemImage: "doc.questionmark")
        }
    }
}

struct ExamEditorView: View {
    enum Mode {
        case new(PendingExam)
        case existing(ExamDocument)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var title = ""
    @State private var subjectID: UUID?
    @State private var date = Date.now
    @State private var grade = ""
    @State private var notes = ""
    @State private var category: DocumentCategory = .exam
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Art"), selection: $category) {
                        ForEach(DocumentCategory.allCases) { Text(DocumentCategoryText.name($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(L("Titel, z. B. 2. Klassenarbeit"), text: $title)
                    Picker(L("Fach"), selection: $subjectID) {
                        Text(L("Kein Fach")).tag(UUID?.none)
                        ForEach(model.subjects) { subject in
                            Label(subject.name, systemImage: subject.symbolName).tag(UUID?.some(subject.id))
                        }
                    }
                    DatePicker(L("Datum"), selection: $date, displayedComponents: .date)
                }
                Section {
                    TextField(L("Note, z. B. 2- oder 11 P."), text: $grade)
                } footer: {
                    Text(L("So, wie sie auf der Arbeit steht. In den Notenrechner fließt sie erst, wenn du sie dort einträgst."))
                }
                Section(L("Notizen")) {
                    TextField(L("Was lief gut, was üben?"), text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                if case .existing(let exam) = mode {
                    Section {
                        Button(L("Prüfung löschen"), role: .destructive) {
                            model.deleteExam(exam.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? L("Neue Prüfung") : L("Prüfung bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern"), action: save)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private func load() {
        guard case .existing(let exam) = mode else { return }
        title = exam.title
        subjectID = exam.subjectID
        date = exam.date
        grade = exam.grade
        notes = exam.notes
        category = exam.kind
    }

    private func save() {
        switch mode {
        case .new(let pending):
            do {
                try model.addExam(pdf: pending.pdf, title: title, subjectID: subjectID, date: date, grade: grade, notes: notes, category: category)
                dismiss()
            } catch {
                problem = L("Die Prüfung konnte nicht gespeichert werden.")
            }
        case .existing(var exam):
            exam.title = title.isEmpty ? exam.title : title
            exam.subjectID = subjectID
            exam.date = date
            exam.grade = grade
            exam.notes = notes
            exam.category = category
            model.update(exam)
            dismiss()
        }
    }
}

/// First visit: what Dokumente is for and the three ways to add one, as a system
/// empty state: scanning is the main action, Fotos and PDF sit beside it.
private struct ExamsWelcome: View {
    let canScan: Bool
    var scan: () -> Void
    var photos: () -> Void
    var files: () -> Void

    var body: some View {
        // Not ContentUnavailableView: inside a List row it squeezes the buttons.
        VStack(spacing: DS.spacingL) {
            VStack(spacing: DS.spacingS) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text(L("Deine Unterlagen an einem Ort"))
                    .font(.title3.weight(.semibold))
                Text(L("Scanne Klassenarbeiten, Arbeitsblätter und Dokumente oder lade Fotos und PDFs. Meldo sortiert sie nach Fach, auch in der Dateien-App."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            // One block: Scannen spans the width, Fotos and PDF split the row below it.
            GlassEffectContainer(spacing: DS.spacingM) {
                VStack(spacing: DS.spacingM) {
                    if canScan {
                        action(L("Scannen"), "doc.viewfinder", prominent: true, scan)
                    }
                    HStack(spacing: DS.spacingM) {
                        action(L("Aus Fotos"), "photo.on.rectangle", prominent: !canScan, photos)
                        action(L("PDF importieren"), "square.and.arrow.down", prominent: false, files)
                    }
                }
            }
            .frame(maxWidth: 400)
            Label(UIDevice.current.userInterfaceIdiom == .pad
                  ? L("Dateien › Auf meinem iPad › Meldo › Scans")
                  : L("Dateien › Auf meinem iPhone › Meldo › Scans"), systemImage: "folder")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(DS.spacingL)
        .padding(.vertical, DS.spacingXL)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    /// Plain buttons with their own glass: system button styles and Label lose their
    /// text inside a List row.
    private func action(_ title: String, _ symbol: String, prominent: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: DS.spacingS) {
                Image(systemName: symbol)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(.capsule)
            .glassEffect(prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// German labels for document categories (the folders keep English names).
enum DocumentCategoryText {
    static func name(_ category: DocumentCategory) -> String {
        switch category {
        case .exam: L("Prüfung")
        case .worksheet: L("Arbeitsblatt")
        case .document: L("Dokument")
        }
    }

    static func plural(_ category: DocumentCategory) -> String {
        switch category {
        case .exam: L("Prüfungen")
        case .worksheet: L("Arbeitsblätter")
        case .document: L("Dokumente")
        }
    }
}
