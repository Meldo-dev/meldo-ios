import Foundation
import MeldoKit
import MeldoState
import MeldoUI
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

nonisolated extension ExamFiles {
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
