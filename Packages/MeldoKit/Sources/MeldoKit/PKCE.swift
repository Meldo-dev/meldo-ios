import CryptoKit
import Foundation
import Security

/// OAuth sign-in with PKCE (Teams and Google).
public nonisolated enum PKCE {
    /// A PKCE verifier, its S256 challenge and a `state`, all random (for one sign-in).
    public static func make() -> (verifier: String, challenge: String, state: String)? {
        func random() -> String? {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
            return base64URL(Data(bytes))
        }
        guard let verifier = random(), let state = random() else { return nil }
        return (verifier, base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))), state)
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
