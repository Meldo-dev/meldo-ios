import Foundation

/// Who sees the first-run tour. Only new students: an existing student who
/// updates already has subjects or a WebUntis connection and never gets it,
/// even though their file predates the "seen" flag.
enum Onboarding {
    static func shouldShow(seen: Bool, hasSubjects: Bool, hasUntis: Bool) -> Bool {
        !seen && !hasSubjects && !hasUntis
    }
}

extension AppModel {
    /// Finished or skipped (including swiping the sheet away): never shown again on its own.
    func finishOnboarding() {
        showingOnboarding = false
        guard !data.preferences.onboardingSeen else { return }
        mutate { $0.preferences.onboardingSeen = true }
    }

    /// From "Einführung ansehen" in Mehr and Über Meldo.
    func showOnboardingAgain() {
        showingOnboarding = true
    }
}
