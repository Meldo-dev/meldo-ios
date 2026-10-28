import MeldoKit
import MeldoState
import MeldoUI
import PDFKit
import SwiftUI
import UIKit

/// Entschuldigung for an absence: filled in from WebUntis and the student's
/// details, rendered as an A4 PDF to print or send. Works for any school: the
/// school name, salutation and signer are filled in or editable.
struct ExcuseNoteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let absence: UntisAbsenceRecord

    @State private var school = ""
    @State private var name = ""
    @State private var className = ""
    @State private var salutation = ""
    /// `nil` until the student picks one; the PDF then keeps a line to fill in by hand.
    @State private var reason: ExcuseReason?
    @State private var otherReason = ""
    @State private var adult = false
    @State private var twoCopies = true
    @State private var pdfURL: URL?
    /// Coming back from the reason list fires onAppear again; filling in again would undo the choice.
    @State private var loaded = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Schule"), text: $school)
                    TextField(L("Dein Name"), text: $name)
                        .textContentType(.name)
                    TextField(L("Klasse"), text: $className)
                } header: {
                    Text(L("Angaben"))
                } footer: {
                    Text(L("Name und Klasse merkt sich Meldo für das nächste Mal."))
                }
                Section {
                    LabeledContent(L("Fehlzeit"), value: ExcuseNote.period(absence))
                    NavigationLink {
                        ExcuseReasonList(selection: $reason)
                    } label: {
                        // Until a reason is picked, the tinted "Bitte wählen" invites the tap.
                        LabeledContent(L("Grund")) {
                            Text(reason?.title ?? L("Bitte wählen"))
                                .foregroundStyle(reason == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                    }
                    .accessibilityIdentifier("excuse-reason")
                    if reason == .other {
                        TextField(L("Grund eingeben"), text: $otherReason, axis: .vertical)
                            .lineLimit(1...3)
                    }
                    TextField(L("Anrede"), text: $salutation, prompt: Text(ExcuseNote.defaultSalutation))
                    Toggle(L("Ich bin volljährig"), isOn: $adult)
                    Toggle(L("Zwei Exemplare pro Seite"), isOn: $twoCopies)
                } footer: {
                    Text(adult
                         ? L("Du unterschreibst die Entschuldigung selbst.")
                         : L("Unterschreiben muss eine erziehungsberechtigte Person."))
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                if let pdfURL {
                    Section {
                        PDFKitView(url: pdfURL)
                            .frame(height: 420)
                            .listRowInsets(EdgeInsets())
                        ShareLink(item: pdfURL) {
                            Label(L("Drucken oder teilen"), systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text(L("Vorschau"))
                    }
                }
            }
            .navigationTitle(L("Entschuldigung"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Schließen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("PDF erstellen"), action: create)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let p = model.preferences
        school = model.data.untis?.schoolName ?? ""
        name = p.studentName
        className = p.className
        salutation = p.excuseSalutation
        adult = p.adultStudent
        let recorded = [absence.reason, absence.text].filter { !$0.isEmpty }.joined(separator: ", ")
        reason = ExcuseReason.guess(from: recorded)
        // Ready under "Sonstiges" if WebUntis recorded something Meldo doesn't know.
        if reason == nil { otherReason = recorded }
    }

    private var reasonText: String {
        guard let reason else { return "" }
        return reason == .other ? otherReason.trimmingCharacters(in: .whitespacesAndNewlines) : reason.title(LGerman)
    }

    private func create() {
        model.setExcuseDetails(name: name, className: className, salutation: salutation, adult: adult)
        let note = ExcuseNote(
            school: school, name: name, className: className,
            salutation: salutation.isEmpty ? ExcuseNote.defaultSalutation : salutation,
            period: ExcuseNote.period(absence), reason: reasonText, adult: adult
        )
        if let url = note.write(twoCopies: twoCopies, fileDate: absence.firstDay) {
            pdfURL = url
            problem = nil
        } else {
            problem = L("Das PDF konnte nicht gespeichert werden.")
        }
    }
}

/// The reasons offered for an Entschuldigung; "Sonstiges" takes the student's own words.
enum ExcuseReason: String, CaseIterable, Identifiable {
    case illness, doctor, family, authority, transport, other

    var id: Self { self }

    var title: String { title(L) }

    /// `LGerman` for the PDF.
    func title(_ localize: (String.LocalizationValue) -> String) -> String {
        switch self {
        case .illness: localize("Krankheit")
        case .doctor: localize("Arzttermin")
        case .family: localize("Familiäre Gründe")
        case .authority: localize("Behördentermin")
        case .transport: localize("Ausfall von Bus oder Bahn")
        case .other: localize("Sonstiges")
        }
    }

    /// The reason WebUntis recorded (school-defined text, e.g. "krank") when Meldo
    /// recognizes it; otherwise `nil`, so the student chooses.
    static func guess(from recorded: String) -> ExcuseReason? {
        let text = recorded.lowercased()
        let keywords: [(ExcuseReason, [String])] = [
            (.illness, ["krank"]),
            (.doctor, ["arzt"]),
            (.family, ["famil"]),
            (.authority, ["behörde"]),
            (.transport, ["bahn", "bus", "verkehr", "fahrplan"]),
        ]
        return keywords.first { _, words in words.contains { text.contains($0) } }?.0
    }
}

/// The reasons as a list; "Sonstiges" comes last. Picking one goes back to the form.
private struct ExcuseReasonList: View {
    @Binding var selection: ExcuseReason?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(ExcuseReason.allCases) { reason in
            Button {
                selection = reason
                dismiss()
            } label: {
                HStack {
                    Text(reason.title).foregroundStyle(.primary)
                    Spacer()
                    if selection == reason {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .accessibilityAddTraits(selection == reason ? .isSelected : [])
        }
        .navigationTitle(L("Grund"))
    }
}

/// The text and layout of the note.
struct ExcuseNote {
    var school: String
    var name: String
    var className: String
    var salutation: String
    var period: String
    var reason: String
    var adult: Bool

    // The PDF goes to a German school: its text is German in every app language.
    private static func L(_ key: String.LocalizationValue) -> String { LGerman(key) }
    private func L(_ key: String.LocalizationValue) -> String { LGerman(key) }

    static var defaultSalutation: String { L("Sehr geehrte Damen und Herren,") }

    /// "am 29.09.2026 (09:35–09:50 Uhr)" or "vom 24.09. bis 25.09.2026".
    static func period(_ absence: UntisAbsenceRecord) -> String {
        let style = Date.FormatStyle(locale: Localization.locale).day(.twoDigits).month(.twoDigits).year()
        let first = absence.firstDay.formatted(style)
        if Calendar.current.isDate(absence.firstDay, inSameDayAs: absence.lastDay) {
            let times = TimeText.range(absence.startMinute, absence.endMinute)
            return L("am \(first) (\(times) Uhr)")
        }
        let last = absence.lastDay.formatted(style)
        return L("vom \(first) bis \(last)")
    }

    private var bodyText: String {
        if adult {
            return L("hiermit bitte ich darum, mein Fehlen \(period) zu entschuldigen.")
        }
        let child = className.isEmpty ? name : "\(name) (\(className))"
        return L("hiermit bitte ich darum, das Fehlen meines Kindes \(child) \(period) zu entschuldigen.")
    }

    /// A4 PDF in Documents/Entschuldigungen (visible in the Files app).
    func write(twoCopies: Bool, fileDate: Date) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { context in
            context.beginPage()
            draw(in: CGRect(x: 60, y: 50, width: page.width - 120, height: 380))
            if twoCopies {
                let cut = UIBezierPath()
                cut.move(to: CGPoint(x: 40, y: page.height / 2))
                cut.addLine(to: CGPoint(x: page.width - 40, y: page.height / 2))
                UIColor.lightGray.setStroke()
                cut.setLineDash([4, 4], count: 2, phase: 0)
                cut.stroke()
                draw(in: CGRect(x: 60, y: page.height / 2 + 30, width: page.width - 120, height: 380))
            }
        }
        guard let base = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        let folder = base.appending(path: "Entschuldigungen", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let day = fileDate.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let url = folder.appending(path: "\(L("Entschuldigung")) \(day).pdf")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        } catch {
            return nil
        }
    }

    private func draw(in rect: CGRect) {
        let serif = UIFont(name: "TimesNewRomanPSMT", size: 12) ?? .systemFont(ofSize: 12)
        let serifBold = UIFont(name: "TimesNewRomanPS-BoldMT", size: 12) ?? .boldSystemFont(ofSize: 12)
        let small = UIFont(name: "TimesNewRomanPSMT", size: 10) ?? .systemFont(ofSize: 10)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        func attributes(_ font: UIFont, _ color: UIColor = .black) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        }
        var y = rect.minY
        func line(_ text: String, _ font: UIFont, color: UIColor = .black, after: CGFloat = 12) {
            let string = NSAttributedString(string: text, attributes: attributes(font, color))
            let height = string.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], context: nil).height
            string.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: height + 2),
                        options: [.usesLineFragmentOrigin], context: nil)
            y += height + after
        }
        func signature(_ label: String) {
            y += 18
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.minX + 200, y: y))
            UIColor.black.setStroke()
            path.lineWidth = 0.6
            path.stroke()
            y += 4
            line(label, small, color: .darkGray, after: 10)
        }

        if !school.isEmpty { line(school, small, color: .darkGray, after: 2) }
        if !name.isEmpty {
            line(className.isEmpty ? name : "\(name) · \(className)", small, color: .darkGray, after: 14)
        }
        line(L("Entschuldigung"), serifBold)
        line(salutation, serif)
        line(bodyText, serif)
        let because = reason.isEmpty ? "______________________________" : reason
        line(L("Grund für das Fehlen: \(because)"), serif)
        line(L("Ich bitte um Verständnis."), serif)
        line(L("Mit freundlichen Grüßen"), serif, after: 4)
        signature(L("Ort, Datum"))
        signature(adult ? L("Unterschrift") : L("Unterschrift der/des Erziehungsberechtigten"))
    }
}
