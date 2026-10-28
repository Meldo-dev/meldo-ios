import SwiftUI

/// Accent color. Few, deliberate choices; Meldo orange is the default.
/// Light/dark is a separate setting (`AppearanceChoice`).
public nonisolated enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case orange, indigo, green

    public var id: String { rawValue }

    public var tint: Color {
        switch self {
        case .orange: .meldoOrange
        case .indigo: .meldoIndigo
        case .green: .green
        }
    }

    /// Clean system backgrounds; the accent carries the color.
    public var wash: Color? { nil }

    public var localizedName: String {
        switch self {
        case .orange: L("Orange")
        case .indigo: L("Indigo")
        case .green: L("Grün")
        }
    }

    /// Themes from version 0.2 (system, light, dark, purple, blue, green, orange).
    public static func migrating(_ raw: String) -> AppTheme {
        switch raw {
        case "purple", "blue", "indigo": .indigo
        case "green": .green
        default: .orange
        }
    }
}

/// Light, dark or following the system.
public nonisolated enum AppearanceChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var localizedName: String {
        switch self {
        case .system: L("System")
        case .light: L("Hell")
        case .dark: L("Dunkel")
        }
    }
}

/// Subject palette backed by system colors, which already adapt to dark mode
/// and Increase Contrast.
public nonisolated enum SubjectColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, brown, gray

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .brown: .brown
        case .gray: .gray
        }
    }
}

/// Meldo brand colors.
nonisolated extension Color {
    public static let meldoIndigo = Color(red: 0x3B / 255, green: 0x3F / 255, blue: 0xD8 / 255)
    public static let meldoIndigoLight = Color(red: 0x8D / 255, green: 0x90 / 255, blue: 0xFF / 255)
    public static let meldoOrange = Color(red: 0xFF / 255, green: 0x9A / 255, blue: 0x4D / 255)
    public static let meldoYellow = Color(red: 0xFF / 255, green: 0xD4 / 255, blue: 0x47 / 255)
    public static let meldoInk = Color(red: 0x14 / 255, green: 0x15 / 255, blue: 0x2A / 255)
}
