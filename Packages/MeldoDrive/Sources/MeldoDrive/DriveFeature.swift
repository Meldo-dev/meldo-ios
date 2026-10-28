import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Google Drive: encrypted sync and backup.
    public static var drive: MeldoFeature {
        var feature = MeldoFeature(id: "drive", title: { L("Google Drive") }, symbol: "externaldrive", placement: .connections) {
            GoogleDriveView()
        }
        feature.badge = { $0.driveState == .needsPassword ? 1 : 0 }
        feature.statusLabel = { model in
            switch model.driveState {
            case .on: AnyView(Text(L("An")))
            case .needsPassword: AnyView(Text(L("Passwort fehlt")).foregroundStyle(.orange))
            case .off: AnyView(Text(L("Aus")))
            }
        }
        feature.install = { $0.installDrive() }
        feature.refresh = { model, _ in await model.syncWithGoogleDrive() }
        feature.refreshOrder = 0
        feature.wantsFrequentWakeUps = { AppModel.storedDriveState() == .on }
        feature.perInstallSecrets = AppModel.perInstallSecrets
        return feature
    }
}
