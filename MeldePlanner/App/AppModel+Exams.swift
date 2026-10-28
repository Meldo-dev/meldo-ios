import Foundation
import PDFKit
import UIKit

/// Dokumente: PDFs in Documents/Scans/<Fach>/<Exams|Worksheets|Documents>,
/// visible in the Files app under "Auf meinem iPhone › Meldo"; metadata in AppData.
extension AppModel {
    enum ExamError: Error {
        case unreadablePDF
        case storage
    }

    /// Sorted newest first.
    var exams: [ExamDocument] {
        data.exams.sorted { $0.date > $1.date }
    }

    func fileURL(for exam: ExamDocument) -> URL? {
        ExamFiles.locate(exam.fileName)
    }

    /// Stores the PDF and records the exam.
    @discardableResult
    func addExam(pdf: Data, title: String, subjectID: UUID?, date: Date, grade: String, notes: String,
                 category: DocumentCategory = .exam) throws(ExamError) -> ExamDocument {
        guard let document = PDFDocument(data: pdf) else { throw .unreadablePDF }
        let id = UUID()
        let subjectName = subjectID.flatMap { subject($0)?.name }
        let folder = ExamFiles.relativeFolder(subject: subjectName, category: category)
        let fileName = folder + "/" + ExamFiles.readableName(title: title, subject: nil, date: date, id: id, in: folder)
        guard let url = ExamFiles.folder()?.appending(path: fileName) else { throw .storage }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try pdf.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw .storage
        }
        let exam = ExamDocument(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("Prüfung") : title,
            subjectID: subjectID, date: date, fileName: fileName,
            pageCount: document.pageCount, grade: grade, notes: notes, category: category
        )
        mutate { $0.exams.append(exam) }
        return exam
    }

    func update(_ exam: ExamDocument) {
        var exam = exam
        exam.updatedAt = currentDate
        mutate { data in
            if let i = data.exams.firstIndex(where: { $0.id == exam.id }) { data.exams[i] = exam }
        }
        organizeDocuments()
    }

    /// Moves every PDF into Scans/<Fach>/<Kategorie> (after a subject or
    /// category change, a renamed subject, or files from older versions).
    func organizeDocuments() {
        let manager = FileManager.default
        guard let root = ExamFiles.folder() else { return }
        var moved: [UUID: String] = [:]
        for exam in data.exams {
            let folder = ExamFiles.relativeFolder(subject: exam.subjectID.flatMap { subject($0)?.name }, category: exam.kind)
            let current = (exam.fileName as NSString).deletingLastPathComponent
            guard current != folder, let source = ExamFiles.locate(exam.fileName),
                  manager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            let name = ExamFiles.readableName(title: exam.title, subject: nil, date: exam.date, id: exam.id, in: folder)
            let target = root.appending(path: folder + "/" + name)
            try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? manager.moveItem(at: source, to: target)) != nil {
                moved[exam.id] = folder + "/" + name
            }
        }
        guard !moved.isEmpty else { return }
        mutate { data in
            for i in data.exams.indices {
                if let path = moved[data.exams[i].id] { data.exams[i].fileName = path }
            }
        }
    }

    func deleteExam(_ id: UUID) {
        // Another exam can use the same file name (merged from another device): keep the file then.
        if let exam = data.exams.first(where: { $0.id == id }),
           !data.exams.contains(where: { $0.id != id && $0.fileName == exam.fileName }),
           let url = fileURL(for: exam) {
            try? FileManager.default.removeItem(at: url)
        }
        mutate { $0.exams.removeAll { $0.id == id } }
    }
}

nonisolated enum ExamFiles {
    /// Larger PDFs are refused instead of read into memory whole.
    static let maxImportBytes = 100 * 1024 * 1024

    /// Whether `url`, with every link resolved, is a regular file in one of the exam folders.
    static func staysInside(_ url: URL) -> Bool {
        let real = url.resolvingSymlinksInPath()
        guard (try? real.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return false }
        let path = real.path(percentEncoded: false)
        let roots = [folder(), documents()?.appending(path: "Prüfungen", directoryHint: .isDirectory), legacyFolder()].compactMap { $0?.resolvingSymlinksInPath().path(percentEncoded: false) }
        return roots.contains { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Documents/Scans: the app shares its Documents folder with the Files app.
    static func folder() -> URL? {
        guard let base = documents() else { return nil }
        let folder = base.appending(path: "Scans", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func documents() -> URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// "Mathematik/Exams"; documents without a subject go to "Other".
    static func relativeFolder(subject: String?, category: DocumentCategory) -> String {
        let name = safe(subject ?? "").isEmpty ? "Other" : safe(subject ?? "")
        return name + "/" + category.folderName
    }

    /// No characters the Files app can't take, no leading dot.
    private static func safe(_ text: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        var result = text.components(separatedBy: unsafe).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        while result.hasPrefix(".") { result.removeFirst() }
        return result
    }

    /// Version 0.2 kept PDFs hidden in Application Support.
    private static func legacyFolder() -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appending(path: "MeldePlanner/Exams", directoryHint: .isDirectory)
    }

    /// A relative path that stays inside the folder it is joined to. Names made on
    /// this device always are; names synced from another device are checked before any file
    /// is read, written, moved or deleted.
    static func isSafe(_ fileName: String) -> Bool {
        let parts = fileName.split(separator: "/", omittingEmptySubsequences: false)
        return !fileName.hasPrefix("/") && !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Where the PDF is now: in Scans, or still in an older location
    /// (Documents/Prüfungen, or Application Support in version 0.2).
    /// `organizeDocuments()` then moves it into place.
    static func locate(_ fileName: String) -> URL? {
        guard isSafe(fileName) else { return nil }
        let manager = FileManager.default
        let candidates = [
            folder()?.appending(path: fileName),
            documents()?.appending(path: "Prüfungen/" + fileName),
            legacyFolder()?.appending(path: fileName),
        ].compactMap { $0 }
        return candidates.first { manager.fileExists(atPath: $0.path(percentEncoded: false)) } ?? candidates.first
    }

    /// "2. Klassenarbeit (12.10.2026).pdf", unique in its folder.
    static func readableName(title: String, subject: String?, date: Date, id: UUID, in relativeFolder: String = "") -> String {
        let day = date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Localization.locale))
        let parts = [subject, title.trimmingCharacters(in: .whitespacesAndNewlines)].compactMap { $0 }.filter { !$0.isEmpty }
        let base = (parts.isEmpty ? L("Prüfung") : parts.joined(separator: ", ")) + " (\(day))"
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        var safe = base.components(separatedBy: unsafe).joined(separator: "-")
        while safe.hasPrefix(".") { safe.removeFirst() }
        var name = "\(safe).pdf"
        if let folder = folder()?.appending(path: relativeFolder) {
            let taken = { (file: String) in FileManager.default.fileExists(atPath: folder.appending(path: file).path(percentEncoded: false)) }
            if taken(name) { name = "\(safe) \(id.uuidString.prefix(4)).pdf" }
            // The short ID can collide too: then the full ID, which is unique.
            if taken(name) { name = "\(safe) \(id.uuidString).pdf" }
        }
        return name
    }

    /// Builds a PDF from scanned pages, downscaled and JPEG-compressed so a
    /// multi-page Klausur stays a few MB.
    static func pdf(from images: [UIImage]) -> Data? {
        let document = PDFDocument()
        for image in images {
            let scaled = downscale(image, maxSide: 2200)
            guard let page = PDFPage(image: scaled, options: [.compressionQuality: 0.6]) else { continue }
            // Append: a skipped image must not leave a gap in the page indices.
            document.insert(page, at: document.pageCount)
        }
        return document.pageCount > 0 ? document.dataRepresentation() : nil
    }

    private static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let factor = maxSide / longest
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
