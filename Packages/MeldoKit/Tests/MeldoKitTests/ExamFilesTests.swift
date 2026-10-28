import Foundation
import Testing
@testable import MeldoKit

/// Regression tests for findings from earlier security reviews.
@Suite("Audit fixes: document files")
struct ExamFilesTests {
    @Test(arguments: [
        ("Mathematik/Exams/1. Klausur (12.10.2026).pdf", true),
        ("Scan.pdf", true),
        ("../../Library/Cookies/Cookies.binarycookies", false),
        ("Mathematik/../../secret", false),
        ("/etc/passwd", false),
        ("Mathematik//x.pdf", false),
        ("./x.pdf", false),
        ("", false),
    ])
    func syncedFileNamesStayInScans(name: String, safe: Bool) {
        #expect(ExamFiles.isSafe(name) == safe)
        #expect((ExamFiles.locate(name) != nil) == safe)
    }

    /// A synced name can also name a folder. Deleting or moving what `locate` returns must
    /// never take a whole folder of PDFs along.
    @Test func aFolderIsNeverADocument() throws {
        let scans = try #require(ExamFiles.folder())
        let folder = "Fach-\(UUID().uuidString)"
        let inside = scans.appending(path: folder + "/Exams/a.pdf")
        try FileManager.default.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("%PDF".utf8).write(to: inside)
        defer { try? FileManager.default.removeItem(at: scans.appending(path: folder)) }

        #expect(ExamFiles.locate(folder) == nil)
        #expect(ExamFiles.locate(folder + "/Exams") == nil)
        #expect(ExamFiles.locate(folder + "/Exams/a.pdf")?.lastPathComponent == "a.pdf")
        #expect(ExamFiles.locate(folder + "/Exams/new.pdf") != nil)
    }
}
