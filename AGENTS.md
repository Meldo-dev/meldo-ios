# AGENTS.md

Guide for AI coding agents working in meldo-ios, the iPhone and iPad app of Meldo.

## What Meldo is

Meldo is a free, open source school planner for students in Germany. Its core feature counts how often a student raises their hand in class (Meldungen). It also has a timetable, homework, exams, grades, a calendar and widgets.

- Apps for iOS, iPadOS and Android. All three share one Rust core (meldo-core).
- No backend and no account. Data stays on the device.
- Optional integrations: Microsoft Teams assignments, and Google Drive backup and sync. Sync data is encrypted on the device before upload (AES-256-GCM, key from PBKDF2-SHA256) and stored in the `drive.appdata` scope.
- German is the default language, English is the second one.
- Website: meldo.dev.

Repos in the Meldo-dev org: `meldo-core`, `meldo-ios`, `meldo-android` (public), `meldo-site`, `meldo-media` (private), `.github` (org profile).

## How this repo works

meldo-ios is the SwiftUI app for iPhone and iPad (iOS 26, Liquid Glass).

| Path | Contents |
|---|---|
| `MeldePlanner/` | App target: entry point, navigation, the feature list `App/FeatureList.swift` |
| `Packages/` | Local Swift packages, one per module |
| `MeldeWidgets/` | Widgets, Live Activity, Control Center button |
| `Shared/` | The Melden intent, compiled into the app and the widgets |
| `MeldeCore/` | Swift package that wraps the Rust core (generated bindings and XCFramework) |
| `core/` | meldo-core as a git submodule |
| `MeldePlannerUITests/` | UI walkthrough and App Store screenshots |
| `Config/` | `Meldo.xcconfig`, `Secrets.example.xcconfig`; `Secrets.xcconfig` is gitignored |
| `scripts/`, `tools/` | Build helpers, string check, security tests, icon and store screenshot renderers |
| `project.yml` | XcodeGen spec; the Xcode project is generated from it |

Modules under `Packages/`:

- Features: MeldoDashboard, MeldoTimetable, MeldoParticipation, MeldoTasks, MeldoGrades, MeldoCalendar, MeldoStatistics, MeldoExams, MeldoSubjects, MeldoOnboarding, MeldoSettings.
- Integrations: MeldoTeams, MeldoDrive (encrypted Drive sync in `DriveSync.swift`).
- Core: MeldoUI (design system, shared rows and sheets, feature registry), MeldoState (`AppModel`), MeldoKit (models, `AppData`, local store, sync merge, localization, engine glue).

How it fits together:

- Dependencies only point down. Features never import each other.
- Each feature describes itself once as a `MeldoFeature`. Tab bar, iPad sidebar, Mehr, Start and Einstellungen are built from `App/FeatureList.swift`. Features link by `MeldoRoute`.
- Grade math, timetable derivation and statistics come from the Rust core through `MeldeCore`. Don't reimplement them in Swift.
- Strings come from `core/l10n/Localizable.xcstrings` (listed in `project.yml`).
- `AppData` and the sync format stay whole, so a build without a feature still reads and syncs all data. The format must match `integration/drive` in meldo-android.
- Check current Apple documentation before using iOS 26 Liquid Glass APIs.

## Build, test and release

Everything needs macOS with Xcode 26.

```bash
git submodule update --init
bash scripts/setup-mac.sh          # tools, Rust core, xcodegen, opens Xcode
bash scripts/build-rust-ios.sh     # after a core bump
xcodegen generate                  # after changing project.yml
python3 scripts/check_strings.py   # every L("...") key exists in the catalog
bash scripts/security-tests.sh     # security regression tests on a simulator
```

Unit tests on a simulator, as CI runs them:

```bash
xcodebuild test -project MeldePlanner.xcodeproj -scheme MeldePlanner \
  -destination "platform=iOS Simulator,name=<iPhone>" \
  -skip-testing:MeldePlannerUITests CODE_SIGNING_ALLOWED=NO
```

Tests live in each package's `Tests/` folder. Device builds need `MELDE_TEAM_ID`.

Workflows:

- `ios.yml`: builds the core, tests `MeldeCore` and the app, builds an unsigned IPA. Runs on pushes to `main` and on pull requests.
- `release.yml`: on a `vX.Y.Z` tag on `main`, `beta` or `alpha`, publishes the unsigned IPA as a GitHub pre-release.
- `testflight.yml`: manual, `main` only, uploads to TestFlight.
- `hygiene.yml`, `ui-review.yml`.

## How to commit

- Commit under your own name and GitHub no-reply email, so the history shows who made each change. Never commit as an AI tool or under someone else's name, and don't change another person's git config.
- If AI helped with a commit, end the message with the trailer `Assisted-by: AI`. No `Co-Authored-By` lines for AI tools and no "Generated with" footers.
- Short imperative commit messages in plain English that say why, for example "Keep the timetable grid within one day".
- Core changes: commit and push meldo-core first, then bump the `core/` submodule in both meldo-ios and meldo-android.
- Every user-facing string goes in `meldo-core/l10n/Localizable.xcstrings`, German first, with an English translation.
- Don't claim a build or test passed unless you ran it and saw the output.

## Allowed and not allowed

- Never put secrets in the repo, code, logs, commits or chat: OAuth client IDs (Google iOS, Google Android, Microsoft Teams), keystore passwords, API keys, tokens. Say where they come from instead: the gitignored `Config/Secrets.xcconfig` on iOS, `~/.gradle/gradle.properties` on Android, GitHub secrets in CI.
- No mention of AI tools, assistant names, private notes or decision record numbers in code, comments or commits. The `hygiene` workflow in the public repos fails on this.
- Participation counts are not grades. Grade logic goes through the scale type (1 to 6, lower is better; 0 to 15, higher is better). Grading rules are configuration, not constants.
- The sync format must stay identical on iOS and Android.
- No new dependency without a stated reason. No mock data shown as real.
- Don't push to `main`, `beta` or `alpha`, and don't create tags or releases, unless the owner asked for it. Work on a branch and open a pull request.
- `beta` and `alpha` differ from `main` on purpose. Don't merge `main` into them, and don't force-push.
- Don't touch the owner's devices or real data.
- The WebUntis import is not part of the apps for now. Don't add it back or reintroduce code for it.
- Site: no third-party requests, cookies or trackers. Keep the `/de/` and `/en/` URLs and the redirects. Legal pages: German is authoritative, English matches it.
