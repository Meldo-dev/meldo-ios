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
}
