import SwiftUI

/// Accent color. Few, deliberate choices; Meldo orange is the default.
/// Light/dark is a separate setting (`AppearanceChoice`).
nonisolated enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case orange, indigo, green

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .orange: .meldoOrange
        case .indigo: .meldoIndigo
        case .green: .green
        }
    }

    /// Clean system backgrounds; the accent carries the color.
    var wash: Color? { nil }

    var localizedName: String {
        switch self {
        case .orange: L("Orange")
        case .indigo: L("Indigo")
        case .green: L("Grün")
        }
    }

    /// Themes from version 0.2 (system, light, dark, purple, blue, green, orange).
    static func migrating(_ raw: String) -> AppTheme {
        switch raw {
        case "purple", "blue", "indigo": .indigo
        case "green": .green
        default: .orange
        }
    }
}

/// Light, dark or following the system.
nonisolated enum AppearanceChoice: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var localizedName: String {
        switch self {
        case .system: L("System")
        case .light: L("Hell")
        case .dark: L("Dunkel")
        }
    }
}

/// Subject palette backed by system colors, which already adapt to dark mode
/// and Increase Contrast.
nonisolated enum SubjectColor: String, Codable, CaseIterable, Identifiable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, brown, gray

    var id: String { rawValue }

    var color: Color {
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
    static let meldoIndigo = Color(red: 0x3B / 255, green: 0x3F / 255, blue: 0xD8 / 255)
    static let meldoIndigoLight = Color(red: 0x8D / 255, green: 0x90 / 255, blue: 0xFF / 255)
    static let meldoOrange = Color(red: 0xFF / 255, green: 0x9A / 255, blue: 0x4D / 255)
    static let meldoYellow = Color(red: 0xFF / 255, green: 0xD4 / 255, blue: 0x47 / 255)
    static let meldoInk = Color(red: 0x14 / 255, green: 0x15 / 255, blue: 0x2A / 255)
}
