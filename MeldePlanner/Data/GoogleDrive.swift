import CryptoKit
import Foundation
import MeldoKit
import MeldoState
import MeldoUI
import Security

/// Google sign-in for Drive sync. OAuth 2.0 + PKCE on Google's own page:
/// Meldo never sees the Google password, only tokens. Meldo is a public "iOS" client,
/// so there is no secret; the client ID is not confidential.
nonisolated enum GoogleConfig {
    /// OAuth client ID of an "iOS" client from Google Cloud Console
    /// ("…apps.googleusercontent.com"). Not in the repo: it comes from MELDO_GOOGLE_CLIENT_ID
    /// (Config/Secrets.xcconfig, a CI secret) through Info.plist. Empty when missing;
    /// Google Drive then shows "noch nicht verfügbar".
    static let clientID = Bundle.main.object(forInfoDictionaryKey: "MeldoGoogleClientID") as? String ?? ""
    /// Only Meldo's own hidden folder in Drive (no access to the student's other files),
    /// plus the account's email address to show which Google account is connected.
    static let scope = "openid email https://www.googleapis.com/auth/drive.appdata"
    static var isConfigured: Bool { !clientID.isEmpty }
    /// Google's redirect for iOS clients: the client ID reversed, as a URL scheme.
    static var callbackScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    static var redirectURI: String { "\(callbackScheme):/oauth2redirect" }
}

nonisolated struct GoogleClient: Sendable {
    nonisolated enum Failure: Error, Equatable {
        case notConfigured
        case cancelled
        case denied(String)
        /// Google doesn't accept the stored sign-in any more (revoked or expired).
        case expired
        case network
    }

    nonisolated struct Tokens: Sendable {
        var access: String
        var refresh: String
        var expires: Date
    }

    /// PKCE verifier, the `state` to expect back and the sign-in URL to open in the
    /// web authentication session.
    static func authorization() -> (verifier: String, state: String, url: URL)? {
        guard GoogleConfig.isConfigured, let (verifier, challenge, state) = TeamsClient.pkce() else { return nil }
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: GoogleConfig.redirectURI),
            URLQueryItem(name: "scope", value: GoogleConfig.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // "consent": Google sends a refresh token again after "trennen" and a new sign-in.
            URLQueryItem(name: "prompt", value: "consent select_account"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components?.url else { return nil }
        return (verifier, state, url)
    }

    /// The `code` (or Google's error) from the redirect back to Meldo. A callback
    /// without this sign-in's `state` didn't come from it and is dropped like a cancel.
    static func code(from callback: URL, state: String) throws(Failure) -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw .cancelled }
        if let code = items.first(where: { $0.name == "code" })?.value { return code }
        let error = items.first { $0.name == "error" }?.value ?? ""
        throw error == "access_denied" ? .cancelled : .denied(error)
    }

    func redeem(code: String, verifier: String) async throws(Failure) -> Tokens {
        try await token([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": GoogleConfig.redirectURI, "code_verifier": verifier,
        ])
    }

    func refresh(_ refreshToken: String) async throws(Failure) -> Tokens {
        try await token(["grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    /// The signed-in account's email address, shown on the Google Drive screen.
    func accountEmail(access: String) async -> String? {
        guard let url = URL(string: "https://openidconnect.googleapis.com/v1/userinfo") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        guard let (data, status) = try? await GoogleDriveFiles.send(request), status == 200 else { return nil }
        return (try? JSONDecoder().decode(GoogleUserInfo.self, from: data))?.email
    }

    /// Ends the sign-in at Google too, so a copied token stops working. Best effort.
    func revoke(_ token: String) async {
        guard let url = URL(string: "https://oauth2.googleapis.com/revoke") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "token", value: token)]
        // "+" means a space in a form body: encode it, or a token containing "+" arrives changed.
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        _ = try? await GoogleDriveFiles.send(request)
    }

    private func token(_ fields: [String: String]) async throws(Failure) -> Tokens {
        guard GoogleConfig.isConfigured, let url = URL(string: "https://oauth2.googleapis.com/token") else { throw .notConfigured }
        var all = fields
        all["client_id"] = GoogleConfig.clientID
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        // "+" means a space in a form body: encode it, or a token containing "+" arrives changed.
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, _) = try await GoogleDriveFiles.send(request)
        guard let response = try? JSONDecoder().decode(GoogleToken.self, from: data) else { throw .network }
        guard let access = response.access_token else {
            if response.error == "invalid_grant" { throw .expired }
            throw .denied(response.error ?? "")
        }
        return Tokens(
            access: access,
            refresh: response.refresh_token ?? fields["refresh_token"] ?? "",
            expires: Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600) - 60)
        )
    }
}

/// The app-data folder of Google Drive through the Drive v3 REST API.
nonisolated struct GoogleDriveFiles: DriveFiles {
    let access: String

    private static let api = "https://www.googleapis.com/drive/v3/files"
    private static let upload = "https://www.googleapis.com/upload/drive/v3/files"

    func list() async throws -> [DriveFile] {
        var files: [DriveFile] = []
        var page: String?
        var pages = 0
        repeat {
            // Meldo writes a few hundred files at most: stop instead of paging forever.
            pages += 1
            guard pages <= 20 else { throw DriveSync.Problem.tooLarge }
            var components = URLComponents(string: Self.api)
            components?.queryItems = [
                URLQueryItem(name: "spaces", value: "appDataFolder"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,createdTime)"),
                URLQueryItem(name: "pageSize", value: "1000"),
            ] + (page.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            guard let url = components?.url else { throw GoogleClient.Failure.network }
            let (data, _) = try await authorized(URLRequest(url: url))
            guard let answer = try? JSONDecoder().decode(FileList.self, from: data) else { throw GoogleClient.Failure.network }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            files += answer.files.compactMap { file in
                guard Self.isID(file.id) else { return nil }
                return DriveFile(id: file.id, name: file.name, created: file.createdTime.flatMap { iso.date(from: $0) } ?? .distantPast)
            }
            page = answer.nextPageToken
        } while page != nil
        return files
    }

    func read(_ id: String, limit: Int) async throws -> Data {
        guard Self.isID(id), let url = URL(string: "\(Self.api)/\(id)?alt=media") else { throw GoogleClient.Failure.network }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await Self.session.bytes(for: request, delegate: GoogleRedirectGuard.shared)
        } catch {
            throw GoogleClient.Failure.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw GoogleClient.Failure.expired }
        guard (200..<300).contains(status) else { throw GoogleClient.Failure.network }
        // Never more than `limit` bytes in memory, whatever the file's size.
        if response.expectedContentLength > Int64(limit) { throw DriveSync.Problem.tooLarge }
        var data = Data()
        data.reserveCapacity(max(0, min(Int(response.expectedContentLength), limit)))
        for try await byte in bytes {
            guard data.count < limit else { throw DriveSync.Problem.tooLarge }
            data.append(byte)
        }
        return data
    }

    func create(_ name: String, data: Data) async throws -> DriveFile {
        guard let url = URL(string: "\(Self.upload)?uploadType=multipart&fields=id,name,createdTime") else { throw GoogleClient.Failure.network }
        let boundary = "meldo-\(UUID().uuidString)"
        let metadata = try JSONEncoder().encode(FileMetadata(name: name))
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body += metadata
        body += Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        body += data
        body += Data("\r\n--\(boundary)--\r\n".utf8)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (answer, _) = try await authorized(request)
        guard let file = try? JSONDecoder().decode(FileList.File.self, from: answer), Self.isID(file.id) else {
            throw GoogleClient.Failure.network
        }
        return DriveFile(id: file.id, name: file.name, created: Date())
    }

    func update(_ id: String, data: Data) async throws {
        guard Self.isID(id), let url = URL(string: "\(Self.upload)/\(id)?uploadType=media") else { throw GoogleClient.Failure.network }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try await authorized(request)
    }

    func delete(_ id: String) async throws {
        guard Self.isID(id), let url = URL(string: "\(Self.api)/\(id)") else { throw GoogleClient.Failure.network }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await authorized(request)
    }

    /// Drive IDs are letters, digits, "-" and "_": an ID from Google's answer can't
    /// change the request path.
    static func isID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 200 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private func authorized(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        var request = request
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, status) = try await Self.send(request)
        if status == 401 { throw GoogleClient.Failure.expired }
        if status == 403 { throw GoogleClient.Failure.denied(String(decoding: data.prefix(200), as: UTF8.self)) }
        guard (200..<300).contains(status) else { throw GoogleClient.Failure.network }
        return (data, status)
    }

    /// No shared cookies or cache, and tokens never follow a redirect to another host.
    private static let session = URLSession(configuration: .ephemeral)

    /// Answers are read up to `limit` (4 MB, like Android): a Drive folder someone filled with
    /// thousands of long names can't make a list or token answer take unbounded memory.
    static func send(_ request: URLRequest, limit: Int = 4 * 1024 * 1024) async throws(GoogleClient.Failure) -> (Data, Int) {
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: GoogleRedirectGuard.shared)
            if response.expectedContentLength > Int64(limit) { throw GoogleClient.Failure.network }
            var data = Data()
            data.reserveCapacity(max(0, min(Int(response.expectedContentLength), limit)))
            for try await byte in bytes {
                guard data.count < limit else { throw GoogleClient.Failure.network }
                data.append(byte)
            }
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw .network
        }
    }
}

/// Same host: followed as is. A download Google moves to its content host
/// (*.googleusercontent.com) is followed without the token; anything else is refused.
nonisolated final class GoogleRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = GoogleRedirectGuard()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(task.originalRequest.flatMap { Self.follow(from: $0, to: request) })
    }

    static func follow(from original: URLRequest, to request: URLRequest) -> URLRequest? {
        guard request.url?.scheme == "https", let to = request.url?.host()?.lowercased() else { return nil }
        if original.url?.host()?.lowercased() == to, (original.url?.port ?? 443) == (request.url?.port ?? 443) { return request }
        guard request.httpMethod == "GET", to.hasSuffix(".googleusercontent.com"), request.url?.port == nil else { return nil }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        stripped.setValue(nil, forHTTPHeaderField: "Cookie")
        return stripped
    }
}

private nonisolated struct FileMetadata: Encodable {
    var name: String
    var parents = ["appDataFolder"]
}

private nonisolated struct GoogleUserInfo: Decodable {
    var email: String?
}

private nonisolated struct GoogleToken: Decodable {
    var access_token: String?
    var refresh_token: String?
    var expires_in: Int?
    var error: String?
}

private nonisolated struct FileList: Decodable {
    nonisolated struct File: Decodable {
        var id: String
        var name: String
        var createdTime: String?
    }

    var files: [File]
    var nextPageToken: String?
}
