import Foundation

/// Finds the App Group this build is actually signed with.
///
/// Sideloading tools that sign with a free Apple ID often rename App Groups
/// (e.g. append the team id), so the name in project.yml may not be the one
/// iOS grants. Resolution order:
/// 1. `ALTAppGroups` in Info.plist (AltStore rewrites it to the real names),
/// 2. the `com.apple.security.application-groups` entitlement embedded in this
///    binary's code signature (works for any signing tool),
/// 3. the name from project.yml.
/// The first candidate iOS actually gives a container for wins.
public nonisolated enum AppGroup: Sendable {
    public static let configured = "group.app.meldeplanner.ios"

    /// The working group id, or `nil` when this build has no usable App Group.
    public static let identifier: String? = candidates().first {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
    }

    public static var containerURL: URL? {
        identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    /// For the diagnostics screen.
    public static var allCandidates: [String] { candidates() }

    private static func candidates() -> [String] {
        var result: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            result += alt
        }
        result += SignedEntitlements.strings("com.apple.security.application-groups")
        result.append(configured)
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }
}

/// Entitlements this build is actually signed with, read from the plist that
/// every code signature embeds as plain XML (works for any signing tool).
public nonisolated enum SignedEntitlements: Sendable {
    public static func strings(_ key: String) -> [String] {
        guard let url = Bundle.main.executableURL,
              let binary = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        let start = Data("<?xml".utf8)
        let end = Data("</plist>".utf8)
        let needle = Data(key.utf8)
        var searchFrom = binary.startIndex
        while let open = binary.range(of: start, in: searchFrom..<binary.endIndex),
              let close = binary.range(of: end, in: open.upperBound..<binary.endIndex) {
            let chunk = binary[open.lowerBound..<close.upperBound]
            if chunk.range(of: needle) != nil,
               let plist = try? PropertyListSerialization.propertyList(from: Data(chunk), format: nil) as? [String: Any],
               let values = plist[key] as? [String] {
                return values
            }
            searchFrom = close.upperBound
        }
        return []
    }
}
