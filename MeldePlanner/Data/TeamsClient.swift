import CryptoKit
import Foundation
import MeldoKit
import MeldoState
import MeldoUI
import Security

/// Microsoft Teams assignments through Microsoft Graph.
///
/// Sign-in uses Microsoft's own page with OAuth 2.0 + PKCE: Meldo never sees
/// the school password, only tokens. Meldo is a public client, so there is no
/// secret; the app (client) ID comes from the school's or the developer's
/// Azure app registration and is not confidential.
nonisolated enum TeamsConfig {
    /// Application (client) ID from the Azure app registration. Not in the repo: it comes
    /// from MELDO_TEAMS_CLIENT_ID (Config/Secrets.xcconfig, a CI secret) through
    /// Info.plist. Empty when missing; Teams then shows how to set it up.
    static let clientID = Bundle.main.object(forInfoDictionaryKey: "MeldoTeamsClientID") as? String ?? ""
    static let redirectURI = "meldeplanner://auth"
    static let callbackScheme = "meldeplanner"
    static let scopes = "offline_access User.Read EduAssignments.ReadBasic EduRoster.ReadBasic"
    static var isConfigured: Bool { !clientID.isEmpty }
}

nonisolated struct TeamsClient: Sendable {
    nonisolated enum Failure: Error, Equatable {
        case notConfigured
        case cancelled
        /// Microsoft refused, e.g. the school's IT hasn't approved Meldo.
        case denied(String)
        case expired
        case network
    }

    nonisolated struct Tokens: Sendable {
        var access: String
        var refresh: String
    }

    nonisolated struct Assignment: Sendable {
        var id: String
        var title: String
        var className: String
        var due: Date?
        var instructions: String
        var webURL: String?
    }

    private static let authority = "https://login.microsoftonline.com/common/oauth2/v2.0"

    /// PKCE verifier, the `state` to expect back and the sign-in URL to open in the
    /// web authentication session.
    static func authorization() -> (verifier: String, state: String, url: URL)? {
        guard let (verifier, challenge, state) = pkce() else { return nil }
        var components = URLComponents(string: "\(authority)/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: TeamsConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: TeamsConfig.redirectURI),
            URLQueryItem(name: "scope", value: TeamsConfig.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components?.url else { return nil }
        return (verifier, state, url)
    }

    /// The `code` (or Microsoft's error) from the redirect back to Meldo. A callback
    /// without this sign-in's `state` didn't come from it and is dropped like a cancel.
    static func code(from callback: URL, state: String) throws(Failure) -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw .cancelled }
        if let code = items.first(where: { $0.name == "code" })?.value { return code }
        let message = items.first { $0.name == "error_description" }?.value
            ?? items.first { $0.name == "error" }?.value ?? ""
        throw .denied(message)
    }

    func redeem(code: String, verifier: String) async throws(Failure) -> Tokens {
        try await token([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": TeamsConfig.redirectURI, "code_verifier": verifier,
        ])
    }

    func refresh(_ refreshToken: String) async throws(Failure) -> Tokens {
        try await token(["grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    private func token(_ fields: [String: String]) async throws(Failure) -> Tokens {
        guard TeamsConfig.isConfigured, let url = URL(string: "\(Self.authority)/token") else { throw .notConfigured }
        var all = fields
        all["client_id"] = TeamsConfig.clientID
        all["scope"] = TeamsConfig.scopes
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        // "+" means a space in a form body: encode it, or a token containing "+" arrives changed.
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let response: GraphToken = try await send(request)
        guard let access = response.access_token else {
            if response.error == "invalid_grant" { throw .expired }
            throw .denied(response.error_description ?? response.error ?? "")
        }
        return Tokens(access: access, refresh: response.refresh_token ?? fields["refresh_token"] ?? "")
    }

    /// The signed-in account's name, for the status screen.
    func accountName(access: String) async throws(Failure) -> String {
        let me: GraphMe = try await graph("me", access: access)
        return me.displayName ?? me.userPrincipalName ?? ""
    }

    /// Assignments of all the student's classes, with class names.
    func assignments(access: String) async throws(Failure) -> [Assignment] {
        let classes: GraphClasses = try await graph("education/me/classes", access: access)
        let names = Dictionary(classes.value.map { ($0.id, $0.displayName ?? "") }, uniquingKeysWith: { a, _ in a })
        let list: GraphAssignments = try await graph("education/me/assignments?$top=100", access: access)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        return list.value
            .filter { $0.status != "draft" }
            .map { item in
                let due = item.dueDateTime.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
                return Assignment(
                    id: item.id,
                    title: item.displayName ?? "",
                    className: item.classId.flatMap { names[$0] } ?? "",
                    due: due,
                    instructions: Self.plainText(item.instructions?.content ?? ""),
                    webURL: item.webUrl
                )
            }
    }

    private func graph<T: Decodable>(_ path: String, access: String) async throws(Failure) -> T {
        guard let url = URL(string: "https://graph.microsoft.com/v1.0/\(path)") else { throw .network }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    /// No shared cookies or cache: tokens and Microsoft's answers stay out of the app-wide stores.
    private static let session = URLSession(configuration: .ephemeral)

    private func send<T: Decodable>(_ request: URLRequest) async throws(Failure) -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request, delegate: SameHostRedirectGuard.shared)
        } catch {
            throw .network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw .expired }
        if status == 403 { throw .denied(String(decoding: data.prefix(200), as: UTF8.self)) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .denied(String(decoding: data.prefix(200), as: UTF8.self))
        }
    }

    /// A PKCE verifier, its S256 challenge and a `state`, all random (Teams and Google sign-in).
    static func pkce() -> (verifier: String, challenge: String, state: String)? {
        func random() -> String? {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
            return base64URL(Data(bytes))
        }
        guard let verifier = random(), let state = random() else { return nil }
        return (verifier, base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))), state)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Assignment instructions arrive as HTML.
    static func plainText(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
        while let open = text.range(of: "<"), let close = text.range(of: ">", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Microsoft Graph answers, decoded off the main actor.

/// Requests that carry a refresh or bearer token (Teams, Google Drive) never follow
/// a redirect to another host.
nonisolated final class SameHostRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = SameHostRedirectGuard()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let from = task.originalRequest?.url, to = request.url
        let same = to?.scheme == "https" && from?.host()?.lowercased() == to?.host()?.lowercased() && (from?.port ?? 443) == (to?.port ?? 443)
        completionHandler(same ? request : nil)
    }
}

private nonisolated struct GraphToken: Decodable {
    var access_token: String?
    var refresh_token: String?
    var error: String?
    var error_description: String?
}

private nonisolated struct GraphMe: Decodable {
    var displayName: String?
    var userPrincipalName: String?
}

private nonisolated struct GraphClasses: Decodable {
    nonisolated struct Class: Decodable {
        var id: String
        var displayName: String?
    }
    var value: [Class]
}

private nonisolated struct GraphAssignments: Decodable {
    nonisolated struct Body: Decodable {
        var content: String?
    }
    nonisolated struct Item: Decodable {
        var id: String
        var displayName: String?
        var classId: String?
        var dueDateTime: String?
        var status: String?
        var webUrl: String?
        var instructions: Body?
    }
    var value: [Item]
}
