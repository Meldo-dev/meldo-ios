import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// The first-run tour: what Meldo is, what Melden means (counting, not
/// grading), one page per area in plain words, and one setup choice.
/// "Überspringen" on every page, no sample data and no permission prompts:
/// those come at the moment a feature needs them. Reopened from Mehr.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var addingSubject = false
    @State private var connectingUntis = false

    private static var lastPage: Int { FeaturePage.all.count + 2 }

    /// After a subject or WebUntis exists the tour has done its job.
    private var isSetUp: Bool { !model.subjects.isEmpty || model.data.untis != nil }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                WelcomePage().tag(0)
                MeldenPage().tag(1)
                ForEach(Array(FeaturePage.all.enumerated()), id: \.offset) { index, feature in
                    feature.tag(index + 2)
                }
                SetupPage(
                    connectUntis: { connectingUntis = true },
                    addSubject: { addingSubject = true },
                    later: model.finishOnboarding
                )
                .tag(Self.lastPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .safeAreaInset(edge: .bottom) {
                // On the last page Weiter ends the tour, like "Später".
                Button {
                    if page < Self.lastPage { next() } else { model.finishOnboarding() }
                } label: {
                    Text(L("Weiter")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, DS.spacingXL)
                .padding(.bottom, DS.spacingS)
                .accessibilityIdentifier("onboarding-next")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSetUp ? L("Fertig") : L("Überspringen"), action: model.finishOnboarding)
                        .accessibilityIdentifier("onboarding-skip")
                }
            }
            .navigationDestination(isPresented: $connectingUntis) { UntisConnectView() }
        }
        .sheet(isPresented: $addingSubject, onDismiss: {
            // A saved subject is enough to start: Melden is now one tap away on Start.
            if !model.subjects.isEmpty { model.finishOnboarding() }
        }) {
            SubjectEditorView(subject: nil)
        }
        .presentationSizing(.form)
        // Connected WebUntis from the tour: the tour has done its job, close it.
        .onChange(of: model.data.untis != nil) { _, connected in
            if connected { model.finishOnboarding() }
        }
    }

    private func next() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0)) {
            page = min(page + 1, Self.lastPage)
        }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        OnboardingPage {
            Mascot(mood: .wave, size: 72)
                .frame(maxWidth: .infinity)
            OnboardingTitle(L("Willkommen bei Meldo"))
            Text(L("Dein Schultag an einem Ort: Melden, Stundenplan, Aufgaben und Noten."))
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DS.spacingS) {
                Text(L("Sprache"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                // One row per language, like the system language list.
                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases) { language in
                        Button { model.setLanguage(language) } label: {
                            HStack {
                                Text(language.nativeName).foregroundStyle(.primary)
                                Spacer()
                                if model.preferences.language == language {
                                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal, DS.spacingL)
                            .padding(.vertical, DS.spacingM)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.preferences.language == language ? .isSelected : [])
                        if language != AppLanguage.allCases.last { Divider().padding(.leading, DS.spacingL) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.rowRadius))
                .accessibilityIdentifier("onboarding-language")
            }
            .padding(.top, DS.spacingS)
        }
    }
}

private struct MeldenPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wave = 0

    var body: some View {
        OnboardingPage {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.wiggle, value: wave)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                .onAppear { if !reduceMotion { wave += 1 } }
            OnboardingTitle(L("Melden mit einem Tipp"))
            Text(L("Hast du dich gemeldet? Tippe auf „Melden“. Meldo ordnet es der laufenden Stunde zu, so siehst du, wie oft du mitmachst."))
                .foregroundStyle(.secondary)
            Label(L("Meldo zählt nur – bewerten tut deine Lehrkraft."), systemImage: "checkmark.seal")
                .font(.headline)
                .padding(DS.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: DS.rowRadius, style: .continuous))
            OnboardingRow(
                symbol: "lock.iphone",
                title: L("Ohne die App zu öffnen"),
                detail: L("Auch über das Kontrollzentrum, den Sperrbildschirm oder die Nachfrage nach der Stunde. Halte dich an die Handyregeln deiner Schule.")
            )
        }
    }
}

/// One area of the app: what it is for, then how to use it, in plain words.
private struct FeaturePage: View {
    let symbol: String
    let title: String
    let intro: String
    var rows: [(symbol: String, title: String, detail: String)]
    var showsLegend = false

    var body: some View {
        OnboardingPage {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            OnboardingTitle(title)
            Text(intro)
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.title) { row in
                OnboardingRow(symbol: row.symbol, title: row.title, detail: row.detail)
            }
            if showsLegend {
                TimetableLegend()
                    .padding(.leading, 36 + DS.spacingM)
            }
        }
    }

    /// Computed, so a language change shows at once.
    static var all: [FeaturePage] { [
        FeaturePage(
            symbol: "tablecells",
            title: L("Stundenplan"),
            intro: L("Hier siehst du deine Woche: welches Fach, welcher Raum, welche Lehrkraft. Wischen bringt dich zur nächsten oder letzten Woche."),
            rows: [
                ("arrow.triangle.2.circlepath", L("Aus WebUntis oder selbst"), L("Verbinde WebUntis, dann kommt dein Plan von allein, mit Vertretungen und Ausfällen. Ohne WebUntis trägst du die Stunden selbst ein.")),
                ("hand.tap", L("Auf eine Stunde tippen"), L("Zeigt alles zur Stunde. Von dort trägst du auch eine Hausaufgabe für dieses Fach ein.")),
                ("ellipsis.circle", L("Menü oben rechts"), L("„Heute“ springt zurück zum heutigen Tag. Dort erklärt Meldo auch, was die Farben bedeuten.")),
                ("a.circle", L("A- und B-Wochen"), L("Hat deine Schule Stunden nur jede zweite Woche? Schalte A/B-Wochen in den Einstellungen ein.")),
            ],
            showsLegend: true
        ),
        FeaturePage(
            symbol: "checklist",
            title: L("Aufgaben und Kalender"),
            intro: L("Alles, was du erledigen musst, an einer Stelle: Hausaufgaben, Lernzettel, eigene To-dos."),
            rows: [
                ("plus.circle", L("Aufgabe eintragen"), L("Fach wählen, und Meldo schlägt als Fälligkeit die nächste Stunde in diesem Fach vor. Du kannst auch ein anderes Datum nehmen.")),
                ("bell", L("Erinnerungen"), L("Lass dich vorher erinnern. Aufgaben, die jede Woche wiederkommen, legt Meldo nach dem Abhaken neu an.")),
                ("tray.and.arrow.down", L("Von WebUntis und Teams"), L("Bist du verbunden, landen Hausaufgaben und Teams-Aufgaben hier von selbst.")),
                ("calendar", L("Kalender"), L("Zeigt Prüfungen, fällige Aufgaben und deine Meldungen über den ganzen Monat.")),
            ]
        ),
        FeaturePage(
            symbol: "graduationcap",
            title: L("Noten und Statistik"),
            intro: L("Trag deine Noten ein, und Meldo rechnet deinen Schnitt pro Fach aus. Das ist deine eigene Rechnung, keine offizielle Note."),
            rows: [
                ("number", L("Noten oder Punkte"), L("Noten 1 bis 6 oder Punkte 0 bis 15, je nach Klasse. Das stellst du unter Noten ein.")),
                ("scalemass", L("Gewichtung"), L("Schriftlich und mündlich zählen oft verschieden. Frag deine Lehrkraft und trag die Gewichtung ein.")),
                ("target", L("Was brauche ich?"), L("Meldo zeigt dir, welche Note du in der nächsten Arbeit brauchst, um dein Ziel zu schaffen.")),
                ("chart.bar", L("Statistik"), L("Wie oft hast du dich gemeldet, pro Tag und pro Fach? Mit Wochenziel und Serie bleibst du dran.")),
            ]
        ),
        FeaturePage(
            symbol: "doc.viewfinder",
            title: L("Dokumente"),
            intro: L("Zurückgegebene Arbeiten, Arbeitsblätter und Zettel: einfach scannen statt verlieren."),
            rows: [
                ("camera", L("Scannen"), L("Halte die Kamera über das Blatt, Meldo schneidet es zu und macht ein PDF daraus. Mehrere Seiten gehen auch.")),
                ("photo.on.rectangle", L("Fotos und PDFs"), L("Schon fotografiert oder als PDF bekommen? Hol es aus deinen Fotos oder der Dateien-App.")),
                ("folder", L("Nach Fach sortiert"), L("Jedes Dokument kommt in den Ordner seines Fachs, auch in der Dateien-App unter Meldo.")),
            ]
        ),
        FeaturePage(
            symbol: "person.crop.circle.badge.clock",
            title: L("Abwesenheiten und Ferien"),
            intro: L("Mit WebUntis siehst du, wann du gefehlt hast und ob es schon entschuldigt ist."),
            rows: [
                ("checkmark.circle", L("Entschuldigt oder offen"), L("Grün ist entschuldigt, rot ist noch offen. Verspätungen zählt Meldo extra.")),
                ("doc.text", L("Entschuldigung schreiben"), L("Halte eine Abwesenheit gedrückt, und Meldo füllt dir eine Entschuldigung zum Ausdrucken oder Teilen vor.")),
                ("sun.horizon", L("Ferien"), L("Ferien und freie Tage kommen aus WebUntis. Dort zeigt der Stundenplan keine Stunden, also fragt Meldo auch nicht nach.")),
            ]
        ),
        FeaturePage(
            symbol: "link",
            title: L("Verbindungen"),
            intro: L("Meldo kann sich mit Diensten verbinden, die du schon nutzt. Alles ist freiwillig, und du kannst es jederzeit wieder trennen."),
            rows: [
                ("arrow.triangle.2.circlepath", L("WebUntis"), L("Stundenplan, Vertretungen, Hausaufgaben, Prüfungen und Abwesenheiten deiner Schule. Du meldest dich mit deinem normalen Schul-Login an.")),
                ("person.3", L("Microsoft Teams"), L("Holt die Aufgaben aus deinen Teams-Klassen. Du schaltest es in den Einstellungen ein, wenn deine Schule es erlaubt.")),
                ("externaldrive", L("Google Drive"), L("Ein verschlüsseltes Backup in deinem eigenen Google Drive, mit all deinen Einstellungen. Beim Einrichten legst du ein Backup Passwort fest; damit öffnest du es auch auf einem neuen Gerät.")),
            ]
        ),
        FeaturePage(
            symbol: "sparkles",
            title: L("Kleine Helfer"),
            intro: L("Meldo funktioniert auch, ohne dass du die App öffnest."),
            rows: [
                ("square.grid.2x2", L("Widgets"), L("Leg Meldo auf den Home- oder Sperrbildschirm: nächste Stunde, offene Aufgaben, Meldungen der Woche.")),
                ("bell.badge", L("Nachfrage nach der Stunde"), L("Auf Wunsch fragt Meldo kurz nach dem Klingeln, ob du dich gemeldet hast. Du antwortest direkt in der Mitteilung.")),
                ("questionmark.circle", L("Diese Einführung"), L("Findest du jederzeit wieder unter Mehr.")),
            ]
        ),
        FeaturePage(
            symbol: "slider.horizontal.3",
            title: L("So, wie du es magst"),
            intro: L("Ein paar Einstellungen, damit Meldo zu dir passt."),
            rows: [
                ("dock.rectangle", L("Leiste und Startseite"), L("Such dir aus, welche zwei Seiten neben Start und Stundenplan in der Leiste stehen und welche Seite Meldo beim Öffnen zeigt.")),
                ("rectangle.3.group", L("Startseite anpassen"), L("Zeig auf der Startseite nur die Karten, die du brauchst, in deiner Reihenfolge.")),
                ("circle.lefthalf.filled", L("Hell oder dunkel"), L("Meldo folgt deinem Gerät. In den Einstellungen kannst du auch immer hell oder immer dunkel wählen.")),
            ]
        ),
        FeaturePage(
            symbol: "lock.shield",
            title: L("Deine Daten bleiben bei dir"),
            intro: L("Meldo hat kein Konto, keinen eigenen Server, keine Werbung und kein Tracking."),
            rows: [
                ("iphone", L("Auf deinem Gerät"), L("Alles, was du einträgst, liegt auf deinem iPhone oder iPad.")),
                ("key", L("Passwörter im Schlüsselbund"), L("Deine Anmeldungen für WebUntis, Teams und Google bleiben im Schlüsselbund dieses Geräts und gehen nie an Meldo.")),
                ("hand.raised", L("Du entscheidest"), L("Daten verlassen dein Gerät nur, wenn du selbst eine Verbindung einschaltest. Mehr dazu steht in der Datenschutzerklärung unter Über Meldo.")),
            ]
        ),
    ] }
}

private struct SetupPage: View {
    var connectUntis: () -> Void
    var addSubject: () -> Void
    var later: () -> Void

    var body: some View {
        OnboardingPage {
            OnboardingTitle(L("Wie startest du?"))
            Text(L("Mit deinem Stundenplan ordnet Meldo jede Meldung der richtigen Stunde zu."))
                .foregroundStyle(.secondary)
            VStack(spacing: DS.spacingM) {
                Button(action: connectUntis) {
                    Label(L("Mit WebUntis verbinden"), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding-untis")
                Text(L("Deine Anmeldung geht direkt an WebUntis, nie an Meldo, und bleibt im Schlüsselbund dieses Geräts."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: addSubject) {
                    Label(L("Fach selbst anlegen"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding-add-subject")
                Button(L("Später"), action: later)
                    .controlSize(.large)
                    .accessibilityIdentifier("onboarding-later")
            }
            .padding(.top, DS.spacingS)
        }
    }
}

// MARK: - Building blocks

/// One page: scrolls when the text is large (Dynamic Type), room at the
/// bottom for the page dots and the button.
private struct OnboardingPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            // Compact, so most pages fit on one screen without scrolling.
            VStack(alignment: .leading, spacing: DS.spacingM) {
                content
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, DS.spacingXL)
            .padding(.top, DS.spacingS)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct OnboardingTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title.weight(.bold))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct OnboardingRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.spacingM) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
