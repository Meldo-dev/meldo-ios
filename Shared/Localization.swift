import Foundation
import Synchronization

/// In-app language switching (German default, Turkish, English).
///
/// Strings live in Localizable.xcstrings with German source keys. Lookups go
/// through the selected language's .lproj bundle, so the app language can
/// differ from the device language without restarting. Thread-safe, because
/// widgets and intents resolve strings off the main thread.
nonisolated enum Localization {
    private struct State: Sendable {
        /// Path of the language's .lproj folder; `nil` falls back to the main bundle.
        var bundlePath: String?
        var locale: Locale
    }

    private static let state = Mutex(State(
        bundlePath: Bundle.main.path(forResource: AppLanguage.german.rawValue, ofType: "lproj"),
        locale: Locale(identifier: AppLanguage.german.rawValue)
    ))

    /// Foundation caches bundles by path, so resolving on each lookup is cheap.
    static var bundle: Bundle {
        state.withLock { $0.bundlePath }.flatMap(Bundle.init(path:)) ?? .main
    }

    static var locale: Locale { state.withLock { $0.locale } }

    static func apply(_ language: AppLanguage) {
        let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
        state.withLock { $0 = State(bundlePath: path, locale: Locale(identifier: language.rawValue)) }
    }
}

/// Always German, whatever the app language: for documents that go to a German school.
nonisolated func LGerman(_ key: String.LocalizationValue) -> String {
    let bundle = Bundle.main.path(forResource: AppLanguage.german.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    return String(localized: key, bundle: bundle, locale: Locale(identifier: AppLanguage.german.rawValue))
}

/// Localized string in the app language.
nonisolated func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: Localization.bundle, locale: Localization.locale)
}
