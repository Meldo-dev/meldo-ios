import Foundation
import MeldeCore

/// Talks to WebUntis. Only two hosts are ever contacted: Untis'
/// school search and the student's own school server. Request bodies and
/// response parsing come from the Rust core (melde-untis).
///
/// A nonisolated struct: with approachable concurrency its async methods run
/// on the caller's actor, so the generated FFI records never cross actors.
nonisolated struct UntisClient: Sendable {
    enum Failure: Error, Equatable {
        case wrongCredentials
        /// The school search matched too many schools; WebUntis then returns none.
        case tooManyResults
        case noAccess(String)
        case server(code: Int64, message: String)
        case network
        /// A browser (SSO) session that has expired or was never logged in.
        case sessionExpired
        /// No lessons in the next eight weeks (holidays or an empty timetable).
        case noLessons
    }

    private static let searchURL = URL(string: "https://mobile.webuntis.com/ms/schoolquery2")!
    /// Own cookie store per client, so the Untis session never mixes with anything else.
    private let session: URLSession
    /// `Cookie` header of a session that was logged in in the browser (school SSO).
    private let browserCookies: String?

    init(browserCookies: String? = nil) {
        self.browserCookies = browserCookies
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = HTTPCookieStorage()
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func searchSchools(_ query: String) async throws(Failure) -> [FfiUntisSchool] {
        let body = try await post(Self.searchURL, body: untisSchoolSearchRequest(query: query))
        do {
            return try map { try untisParseSchoolSearch(body: body) }
        } catch .server(code: -6003, _) {
            throw .tooManyResults
        }
    }

    func login(server: String, loginName: String, user: String, password: String) async throws(Failure) -> FfiUntisAuth {
        let body = try await post(try endpoint(server, loginName), body: untisAuthenticateRequest(user: user, password: password))
        return try map { try untisParseAuth(body: body) }
    }

    /// Who is logged in, for a session that started in the browser (Microsoft 365 or
    /// another school login) instead of `authenticate`.
    func browserAuth(server: String, sessionID: String) async throws(Failure) -> FfiUntisAuth {
        let probe = await probeBrowserLogin(server: server, sessionID: sessionID)
        // No answer at all means offline, not an expired session.
        guard let auth = probe.auth else { throw probe.reachable ? .sessionExpired : .network }
        return auth
    }

    /// Asks `/api/app/config`, then the newer `/api/rest/view/v1/app/data`.
    /// `detail` says what WebUntis answered, for the login screen when it fails;
    /// `reachable` is false when no request got an answer.
    func probeBrowserLogin(server: String, sessionID: String) async -> (auth: FfiUntisAuth?, detail: String, reachable: Bool) {
        var notes: [String] = []
        var answered = false
        func url(_ path: String) -> URL? {
            var components = URLComponents()
            components.scheme = "https"
            components.host = server
            components.path = path
            return components.url
        }
        // The newer REST API wants the session's JWT as well.
        var token: String?
        if let tokenURL = url("/WebUntis/api/token/new"),
           let (status, body) = try? await sendWithStatus(URLRequest(url: tokenURL)),
           status == 200, !body.isEmpty, !body.hasPrefix("<") {
            token = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for path in ["/WebUntis/api/app/config", "/WebUntis/api/rest/view/v1/app/data"] {
            guard let url = url(path) else { continue }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token, path.contains("/rest/") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            guard let (status, body) = try? await sendWithStatus(request) else {
                notes.append("\(path): keine Verbindung")
                continue
            }
            answered = true
            let auth = path.hasSuffix("config")
                ? try? untisParseAppConfig(body: body, sessionId: sessionID)
                : try? untisParseAppData(body: body, sessionId: sessionID)
            if let auth { return (auth, "", true) }
            let start = body.prefix(80).replacingOccurrences(of: "\n", with: " ")
            notes.append("\(path): HTTP \(status) \(start)")
        }
        return (nil, ([server] + notes).joined(separator: "\n"), answered)
    }

    /// GET on the WebUntis web API with this client's session.
    private func webGet(server: String, path: String, query: String) async throws(Failure) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = server
        components.path = path
        components.percentEncodedQuery = query
        guard let url = components.url else { throw .network }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    func absences(server: String, auth: FfiUntisAuth, first: FfiDate, last: FfiDate) async throws(Failure) -> [FfiUntisAbsence] {
        let range = try map { try untisRangeQuery(first: first, last: last) }
        let body = try await webGet(server: server, path: "/WebUntis/api/classreg/absences/students",
                                    query: range + "&studentId=\(auth.personId)&excuseStatusId=-1")
        return try map { try untisParseAbsences(body: body) }
    }

    func exams(server: String, auth: FfiUntisAuth, first: FfiDate, last: FfiDate) async throws(Failure) -> [FfiUntisExam] {
        let range = try map { try untisRangeQuery(first: first, last: last) }
        let body = try await webGet(server: server, path: "/WebUntis/api/exams",
                                    query: range + "&studentId=\(auth.personId)&klasseId=\(auth.klasseId ?? -1)&withGrades=false")
        return try map { try untisParseExams(body: body) }
    }

    /// Exams marked in the REST timetable, which the web app and the Untis apps use.
    /// For schools that refuse `/api/exams` to students (HTTP 403).
    func timetableExams(server: String, auth: FfiUntisAuth, first: FfiDate, last: FfiDate) async throws(Failure) -> [FfiUntisExam] {
        var tokenComponents = URLComponents()
        tokenComponents.scheme = "https"
        tokenComponents.host = server
        tokenComponents.path = "/WebUntis/api/token/new"
        guard let tokenURL = tokenComponents.url else { throw .network }
        let token = try await sendWithStatus(URLRequest(url: tokenURL)).body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.hasPrefix("<") else { throw .sessionExpired }
        let query = try map { try untisTimetableEntriesQuery(personId: auth.personId, first: first, last: last) }
        var components = URLComponents()
        components.scheme = "https"
        components.host = server
        guard let base = components.url, let url = URL(string: query, relativeTo: base)?.absoluteURL,
              url.host()?.lowercased() == server.lowercased() else { throw .network }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body = try await send(request)
        return try map { try untisParseTimetableExams(body: body) }
    }

    func homework(server: String, first: FfiDate, last: FfiDate) async throws(Failure) -> [FfiUntisHomework] {
        let range = try map { try untisRangeQuery(first: first, last: last) }
        let body = try await webGet(server: server, path: "/WebUntis/api/homeworks/lessons", query: range)
        return try map { try untisParseHomework(body: body) }
    }

    func news(server: String, date: FfiDate) async throws(Failure) -> [FfiUntisNews] {
        let day = String(format: "%04d%02d%02d", Int(date.year), Int(date.month), Int(date.day))
        let body = try await webGet(server: server, path: "/WebUntis/api/public/news/newsWidgetData", query: "date=\(day)")
        return try map { try untisParseNews(body: body) }
    }

    /// The school's bell schedule (periods; breaks are the gaps).
    func timegrid(server: String, loginName: String) async throws(Failure) -> [FfiTimeUnit] {
        let body = try await post(try endpoint(server, loginName), body: untisTimegridRequest())
        return try map { try untisParseTimegrid(body: body) }
    }

    /// The school year's holidays (Herbstferien, Weihnachtsferien, …).
    func holidays(server: String, loginName: String) async throws(Failure) -> [FfiUntisHoliday] {
        let body = try await post(try endpoint(server, loginName), body: untisHolidaysRequest())
        return try map { try untisParseHolidays(body: body) }
    }

    /// Raw `getTimetable` JSON for `first...last`, parsed later by Rust.
    func timetable(server: String, loginName: String, auth: FfiUntisAuth, first: FfiDate, last: FfiDate) async throws(Failure) -> String {
        let request = try map { try untisTimetableRequest(personId: auth.personId, personType: auth.personType, first: first, last: last) }
        return try await post(try endpoint(server, loginName), body: request)
    }

    func logout(server: String, loginName: String) async {
        _ = try? await post(try endpoint(server, loginName), body: untisLogoutRequest())
    }

    /// The school's JSON-RPC endpoint. A server that isn't a plain host name is an error,
    /// never a fallback to another host: the password would go wherever the URL points.
    private func endpoint(_ server: String, _ loginName: String) throws(Failure) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        let host = server.lowercased()
        components.host = host
        components.path = "/WebUntis/jsonrpc.do"
        components.queryItems = [URLQueryItem(name: "school", value: loginName)]
        guard untisIsValidHost(host: host), let url = components.url else { throw .network }
        return url
    }

    private func post(_ url: URL, body: String) async throws(Failure) -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws(Failure) -> String {
        try await sendWithStatus(request).body
    }

    private func sendWithStatus(_ request: URLRequest) async throws(Failure) -> (status: Int, body: String) {
        // Every request goes over HTTPS to a plain host name (Untis' search or the school).
        guard let url = request.url, url.scheme == "https", let host = url.host()?.lowercased(),
              untisIsValidHost(host: host) else { throw .network }
        var request = request
        if let browserCookies { request.setValue(browserCookies, forHTTPHeaderField: "Cookie") }
        do {
            // Stream with a cap: a reached server (malicious, compromised or a MITM of the
            // HTTPS host) can't exhaust memory with a huge body. A normal response is tens of KB.
            let (bytes, response) = try await session.bytes(for: request, delegate: UntisRedirectGuard.shared)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if response.expectedContentLength > Int64(Self.maxResponseBytes) { throw Failure.network }
            var data = Data()
            data.reserveCapacity(max(0, min(Int(response.expectedContentLength), Self.maxResponseBytes)))
            for try await byte in bytes {
                guard data.count < Self.maxResponseBytes else { throw Failure.network }
                data.append(byte)
            }
            return (status, String(decoding: data, as: UTF8.self))
        } catch {
            throw .network
        }
    }

    /// A WebUntis response never legitimately runs to megabytes; cap it so a reached server
    /// can't exhaust memory. Well above a real timetable, well below a harmful allocation.
    private static let maxResponseBytes = 8 * 1024 * 1024

    private func map<T>(_ work: () throws -> T) throws(Failure) -> T {
        do {
            return try work()
        } catch let MeldeError.UntisServer(code, message) {
            throw code == -8504 ? .wrongCredentials : .server(code: code, message: message)
        } catch let MeldeError.UntisMalformed(message) {
            throw .noAccess(message)
        } catch {
            throw .noAccess("\(error)")
        }
    }
}

/// Keeps the student's WebUntis password, session and tokens on the school's server:
/// a redirect away from HTTPS is refused, a POST (the login body carries the
/// password) never follows a redirect to another host, and a GET to another host
/// must be a valid server name and loses the `Cookie` and `Authorization` headers.
nonisolated final class UntisRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = UntisRedirectGuard()

    // The completion-handler form: the async one crashes the Swift 6.4 compiler here.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(task.originalRequest.flatMap { Self.follow(from: $0, to: request) })
    }

    /// The request to send for a redirect, or `nil` to stop there.
    static func follow(from original: URLRequest, to request: URLRequest) -> URLRequest? {
        guard request.url?.scheme == "https", let to = request.url?.host()?.lowercased() else { return nil }
        // Another port is another server, and the cookie store would still send it the
        // school's cookies (cookies ignore ports): never go there.
        guard (original.url?.port ?? 443) == (request.url?.port ?? 443) else { return nil }
        guard original.url?.host()?.lowercased() != to else { return request }
        guard original.httpMethod != "POST", request.httpMethod != "POST", untisIsValidHost(host: to) else { return nil }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Cookie")
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }
}

