import Foundation

/// Where document PDFs live: Documents/Scans/<Fach>/<Kategorie>, shared with the Files app.
public nonisolated enum ExamFiles: Sendable {
    /// Larger PDFs are refused instead of read into memory whole.
    public static let maxImportBytes = 100 * 1024 * 1024

    /// Whether `url`, with every link resolved, is a regular file in one of the exam folders.
    public static func staysInside(_ url: URL) -> Bool {
        let real = url.resolvingSymlinksInPath()
        guard (try? real.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return false }
        let path = real.path(percentEncoded: false)
        let roots = [folder(), documents()?.appending(path: "Prüfungen", directoryHint: .isDirectory), legacyFolder()].compactMap { $0?.resolvingSymlinksInPath().path(percentEncoded: false) }
        return roots.contains { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Documents/Scans: the app shares its Documents folder with the Files app.
    public static func folder() -> URL? {
        guard let base = documents() else { return nil }
        let folder = base.appending(path: "Scans", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func documents() -> URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// "Mathematik/Exams"; documents without a subject go to "Other".
    public static func relativeFolder(subject: String?, category: DocumentCategory) -> String {
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
    public static func isSafe(_ fileName: String) -> Bool {
        let parts = fileName.split(separator: "/", omittingEmptySubsequences: false)
        return !fileName.hasPrefix("/") && !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Where the PDF is now: in Scans, or still in an older location
    /// (Documents/Prüfungen, or Application Support in version 0.2).
    /// `organizeDocuments()` then moves it into place.
    public static func locate(_ fileName: String) -> URL? {
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
    public static func readableName(title: String, subject: String?, date: Date, id: UUID, in relativeFolder: String = "") -> String {
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
}
