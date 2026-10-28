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
            L("Passwörter und Anmeldungen"),
            L("Dein WebUntis-Passwort oder deine Schul-Anmeldung, die Anmeldung bei Microsoft und die Anmeldung bei Google werden nur im Schlüsselbund dieses Geräts gespeichert. Sie werden weder synchronisiert noch in Backups übertragen. Auf einem neuen Gerät meldest du dich deshalb erneut an.")
        ),
        (
            L("WebUntis"),
            L("Wenn du WebUntis verbindest, meldet sich Meldo direkt beim WebUntis-Server deiner Schule an und lädt deinen Stundenplan, Vertretungen, Abwesenheiten, Prüfungen, Hausaufgaben und Mitteilungen der Schule. Die Daten fließen nur zwischen deinem Gerät und diesem Server. Für die Verarbeitung dort sind deine Schule und der Anbieter Untis verantwortlich. Solange die Verbindung besteht, fragt Meldo dort regelmäßig nach Änderungen, auch im Hintergrund, etwa alle 30 Minuten.")
        ),
        (
            L("Microsoft Teams"),
            L("Wenn du Teams verbindest, meldest du dich auf der Seite von Microsoft an. Meldo liest dann deine Aufgaben aus Teams über die Schnittstelle von Microsoft und speichert sie als Hausaufgaben auf deinem Gerät. Meldo sieht dein Microsoft-Passwort nicht. Meldo sucht höchstens alle drei Stunden nach neuen Aufgaben, auch im Hintergrund. Microsoft kann Daten außerhalb der EU verarbeiten; dafür gelten die Bedingungen von Microsoft und deiner Schule.")
        ),
        (
            L("Backup in Google Drive"),
            L("Wenn du das Backup einschaltest, speichert Meldo deine Daten und Dokumente in einem versteckten Ordner in deinem Google Drive. Vorher werden sie auf deinem Gerät mit deinem Backup-Passwort verschlüsselt. Google kann den Inhalt nicht lesen, sieht aber Anzahl, Größe und Zeitpunkt der Dateien. Meldo hat nur Zugriff auf diesen eigenen Ordner, nicht auf deine anderen Dateien. Außerdem liest Meldo die E-Mail-Adresse deines Google-Kontos, um anzuzeigen, welches Konto verbunden ist. Google kann die verschlüsselten Dateien auf Servern außerhalb der EU speichern.")
        ),
        (
            L("Mitteilungen und Live-Aktivität"),
            L("Erinnerungen, die Frage nach jeder Stunde und die Live-Aktivität werden auf deinem Gerät erzeugt. Dafür sendet Meldo keine Daten an einen Server.")
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
            L("Kinder und Jugendliche"),
            L("Meldo ist für Schülerinnen und Schüler gemacht, auch unter 16 Jahren. Meldo selbst erhebt keine Daten. Für die Anmeldung bei WebUntis, Microsoft und Google gelten die Regeln deiner Schule und dieser Anbieter. Bist du unter 16, sprich mit deinen Eltern, bevor du Microsoft oder Google verbindest.")
        ),
        (
            L("Deine Rechte"),
            L("Da Meldo deine Daten nicht auf einem eigenen Server speichert, kann der Entwickler sie weder einsehen noch herausgeben. Anfragen zu Daten bei WebUntis, Microsoft oder Google richtest du an deine Schule oder an den jeweiligen Anbieter. Deine Rechte nach der Datenschutz-Grundverordnung (DSGVO) gelten dort weiterhin.")
        ),
        (
            L("Verantwortlich und Kontakt"),
            L("Meldo wird von Yavuz Selim Kolbasar als kostenloses, nicht-kommerzielles Projekt entwickelt. Bei Fragen zum Datenschutz erreichst du den Entwickler unter contact@meldo.dev. Meldo ist Open Source: Den Quellcode kannst du auf GitHub selbst prüfen. Meldo ist kein Angebot von Untis, Microsoft oder Google und steht mit ihnen in keiner Verbindung.")
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
