import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

/// The privacy policy: what Meldo stores, where, and what leaves the device.
/// Meldo has no server of its own; every connection is to a service the student
/// turns on (WebUntis, Microsoft Teams, Google Drive).
struct PrivacyPolicyView: View {
    @Environment(\.features) private var features

    /// Computed, so a language change shows at once.
    private static var sections: [(title: String, body: String)] { [
        (
            L("Kurz gesagt"),
            L("Meldo hat keinen eigenen Server und kein Konto. Wir zeigen keine Werbung, nutzen kein Tracking und keine Analyse-Dienste. Deine Daten werden auf deinem Gerät gespeichert. Nur wenn du WebUntis, Microsoft Teams oder Google Drive selbst verbindest, tauscht Meldo Daten mit diesen Diensten aus.")
        ),
        (
            L("Was auf deinem Gerät gespeichert wird"),
            L("Fächer, Stundenplan, Meldungen, Noten, Aufgaben, Ferien, Abwesenheiten, Einstellungen, eingescannte oder importierte Dokumente sowie Entschuldigungen, die du in Meldo erstellst. Dokumente und Entschuldigungen liegen im Meldo-Ordner der Dateien-App. Eine Entschuldigung kann einen Grund wie Krankheit enthalten; Meldo merkt sich dafür deinen Namen und deine Klasse. Widgets und der Melden-Knopf lesen dieselben Daten auf diesem Gerät.")
        ),
        (
            L("Scannen, Fotos und Dateien"),
            L("Zum Scannen nutzt Meldo den Dokumentenscanner von Apple. Die Seiten werden auf deinem Gerät erfasst und als PDF in Meldo gespeichert. Bei Fotos bekommt Meldo nur die Bilder, die du auswählst. PDFs wählst du in der Dateien-App aus. Dafür sendet Meldo keine Daten an einen Server.")
        ),
        (
            L("Passwörter und Anmeldungen"),
            L("Dein WebUntis-Passwort oder deine Schul-Anmeldung, die Anmeldung bei Microsoft und die Anmeldung bei Google werden nur im Schlüsselbund dieses Geräts gespeichert. Sie werden weder synchronisiert noch in Backups übertragen. Auf einem neuen Gerät meldest du dich deshalb erneut an.")
        ),
        (
            L("WebUntis"),
            L("Wenn du WebUntis verbindest, meldet sich Meldo direkt beim WebUntis-Server deiner Schule an und lädt deinen Stundenplan, Vertretungen, Abwesenheiten, Prüfungen, Hausaufgaben und Mitteilungen der Schule. Um deine Schule zu finden, schickt Meldo deinen Suchbegriff an die Schulsuche von WebUntis. Die Daten fließen nur zwischen deinem Gerät und Untis. Für die Verarbeitung dort sind deine Schule und der Anbieter Untis verantwortlich. Solange die Verbindung besteht, fragt Meldo dort regelmäßig nach Änderungen: bei geöffneter App etwa alle 30 Sekunden, im Hintergrund etwa alle 20 Minuten. Den genauen Zeitpunkt bestimmt dein Gerät.")
        ),
        (
            L("Microsoft Teams"),
            L("Wenn du Teams verbindest, meldest du dich auf der Seite von Microsoft an. Meldo liest dann über die Schnittstelle von Microsoft deine Aufgaben, deine Klassen und deinen Namen (oder, falls keiner hinterlegt ist, deine Schul-E-Mail-Adresse) und bleibt angemeldet. Die Aufgaben speichert Meldo als Hausaufgaben auf deinem Gerät. Deinen Namen und die Namen deiner Klassen zeigt Meldo nur in der App an. Meldo sieht dein Microsoft-Passwort nicht. Meldo sucht höchstens alle drei Stunden nach neuen Aufgaben, auch im Hintergrund. Microsoft kann Daten außerhalb der EU verarbeiten; dafür gelten die Bedingungen von Microsoft und deiner Schule.")
        ),
        (
            L("Backup in Google Drive"),
            L("Wenn du das Backup einschaltest, speichert Meldo deine Daten und Dokumente in einem versteckten Ordner in deinem Google Drive. Vorher werden sie auf deinem Gerät mit deinem Backup-Passwort verschlüsselt. Google kann den Inhalt nicht lesen, sieht aber Anzahl, Größe und Zeitpunkt der Dateien. Meldo hat nur Zugriff auf diesen eigenen Ordner, nicht auf deine anderen Dateien. Außerdem liest Meldo die E-Mail-Adresse deines Google-Kontos, um anzuzeigen, welches Konto verbunden ist. Google kann die verschlüsselten Dateien auf Servern außerhalb der EU speichern. Die Nutzung von Informationen, die Meldo von Google-APIs erhält, und ihre Übertragung an andere Apps entsprechen der Google API Services User Data Policy, einschließlich der Anforderungen zur eingeschränkten Nutzung (Limited Use).")
        ),
        (
            L("Mitteilungen und Live-Aktivität"),
            L("Erinnerungen, die Frage nach jeder Stunde und die Live-Aktivität werden auf deinem Gerät erzeugt. Dafür sendet Meldo keine Daten an einen Server. Mitteilungen, die Live-Aktivität und Widgets auf dem Sperrbildschirm oder im StandBy-Modus zeigen Fächer und Aufgaben auch, wenn dein Gerät gesperrt ist. Das änderst du in den Einstellungen deines Geräts oder indem du das Widget entfernst.")
        ),
        (
            L("Backups deines Geräts"),
            L("Wenn dein iPhone oder iPad ein Backup in iCloud oder auf einem Computer erstellt, sind deine Meldo-Daten darin enthalten. Passwörter und Anmeldungen sind davon ausgenommen.")
        ),
        (
            L("Daten löschen"),
            L("Du kannst einzelne Einträge in der App löschen. Wenn du Meldo vom Gerät löschst, werden deine Meldo-Daten auf diesem Gerät entfernt. Anmeldungen im Schlüsselbund kann iOS auch danach behalten; trennst du die Verbindungen vorher in der App, sind sie sofort gelöscht. Kann Meldo seine Datei einmal nicht lesen, hebt es eine Kopie höchstens 30 Tage auf, damit nichts verloren geht. Verbindungen zu WebUntis, Teams und Google Drive kannst du jederzeit in der App trennen. Das Backup in Google Drive löschst du unter Mehr > Google Drive > Backup in Google Drive löschen.")
        ),
        (
            L("Rechtsgrundlage"),
            L("Was du in Meldo einträgst, bleibt auf deinem Gerät. Deine Einträge bekommt der Entwickler nicht. Meldo verarbeitet deine Einträge und die Verbindungen, die du einschaltest, weil das nötig ist, damit du Meldo wie in den Nutzungsbedingungen beschrieben nutzen kannst (Art. 6 Abs. 1 lit. b DSGVO). Meldo stützt sich auf keine Einwilligung. Tippst du bei Google oder Microsoft auf „Zulassen“, bekommt Meldo dort Zugriff. Für die Verarbeitung auf ihrer Seite sind diese Anbieter oder deine Schule verantwortlich.")
        ),
        (
            L("Kinder und Jugendliche"),
            L("Meldo ist für Schülerinnen und Schüler gemacht, auch unter 16 Jahren. Der Entwickler sammelt über Meldo keine Daten über dich. Für die Anmeldung bei WebUntis, Microsoft und Google gelten die Regeln deiner Schule und dieser Anbieter. Bist du unter 16, sprich mit deinen Eltern, bevor du Microsoft oder Google verbindest.")
        ),
        (
            L("Deine Rechte"),
            L("Da Meldo deine Einträge nicht auf einem eigenen Server speichert, kann der Entwickler sie weder einsehen noch herausgeben. Hast du in den Einstellungen deines Geräts erlaubt, Analysedaten mit App-Entwicklern zu teilen, gibt Apple Absturzberichte ohne deinen Namen an den Entwickler weiter. Sie enthalten Gerätemodell, Systemversion und die Stelle im Code, aber keine Meldo-Einträge, und dienen nur dazu, Fehler zu beheben (Art. 6 Abs. 1 lit. f DSGVO). Anfragen zu Daten bei WebUntis, Microsoft oder Google richtest du an deine Schule oder an den jeweiligen Anbieter. Deine Rechte nach der Datenschutz-Grundverordnung (DSGVO) gelten dort weiterhin. Du hast das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit, Widerspruch und Beschwerde bei einer Aufsichtsbehörde. Widerspruchsrecht: Verarbeiten wir Daten nach Art. 6 Abs. 1 lit. f DSGVO, kannst du dem jederzeit widersprechen, per E-Mail an contact@meldo.dev. Die ganze Datenschutzerklärung findest du unter meldo.dev/de/privacy.")
        ),
        (
            L("Verantwortlich und Kontakt"),
            L("Meldo wird von Yavuz Selim Kolbasar als kostenloses, nicht-kommerzielles Projekt entwickelt. Bei Fragen zum Datenschutz erreichst du den Entwickler unter contact@meldo.dev. Meldo ist Open Source: Den Quellcode kannst du auf GitHub selbst prüfen. Meldo ist kein Angebot von Untis, Microsoft oder Google und steht mit ihnen in keiner Verbindung.")
        ),
        (
            L("Widerspruchsrecht"),
            L("Verarbeitet der Entwickler Daten nach Art. 6 Abs. 1 lit. f DSGVO (Absturzberichte, E-Mails), kannst du dem jederzeit widersprechen, per E-Mail an contact@meldo.dev.")
        ),
    ] }

    /// Sections about a connection that may be left out of the build, by their title.
    private static func feature(of title: String) -> String? {
        [L("WebUntis"): "untis", L("Microsoft Teams"): "teams", L("Backup in Google Drive"): "drive"][title]
    }

    var body: some View {
        List {
            ForEach(Self.sections.filter { Self.feature(of: $0.title).map { features.feature($0) != nil } ?? true }, id: \.title) { section in
                Section(section.title) {
                    Text(section.body)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(L("Datenschutzerklärung"))
    }
}
