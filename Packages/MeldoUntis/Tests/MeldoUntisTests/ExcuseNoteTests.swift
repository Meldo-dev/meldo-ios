import MeldoKit
import MeldoState
import Testing
@testable import MeldoUntis

@Suite("Entschuldigung")
struct ExcuseNoteTests {
    @Test(arguments: [
        ("", nil),
        ("  ", nil),
        ("krank", ExcuseReason.illness),
        ("Krankheit", .illness),
        ("Arztbesuch", .doctor),
        ("familiäre Gründe", .family),
        ("Termin bei der Behörde", .authority),
        ("Bahn ausgefallen", .transport),
        ("unbekannt, Fahrplanänderung", .transport),
        ("Führerscheinprüfung", nil),
    ] as [(String, ExcuseReason?)])
    func reasonFromWebUntis(recorded: String, expected: ExcuseReason?) {
        #expect(ExcuseReason.guess(from: recorded) == expected)
    }
}
