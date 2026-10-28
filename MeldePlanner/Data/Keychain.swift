import Foundation
import Security

/// Minimal Keychain wrapper for the WebUntis password. Stored only on this
/// device (not in backups or iCloud Keychain) and readable after first unlock.
nonisolated enum Keychain {
    private static let service = "app.meldeplanner.webuntis"

    /// Replaces the secret in place, so a failed write never loses the old one.
    static func save(_ secret: String, account: String) -> Bool {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let values: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(secret.utf8),
        ]
        let status = SecItemUpdate(match as CFDictionary, values as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        return SecItemAdd(match.merging(values) { $1 } as CFDictionary, nil) == errSecSuccess
    }

    /// Removes every Meldo secret on this device.
    static func deleteAll() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
    }

    /// Keychain items outlive the app. A fresh install (nothing connected, never run
    /// before) starts without the secrets an earlier install left behind; `alwaysForget`
    /// accounts (Google Drive) go even when the restored data still has a connection.
    static func forgetEarlierInstall(hasConnection: Bool, alwaysForget: [String] = [], defaults: UserDefaults = .standard) {
        let marker = "keychain.installed"
        guard !defaults.bool(forKey: marker) else { return }
        if !hasConnection { deleteAll() } else { alwaysForget.forEach { delete(account: $0) } }
        defaults.set(true, forKey: marker)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
