import Foundation
import MeldeCore
import MeldoKit
import MeldoState
import MeldoUI
import UIKit
import WebKit

/// Renews an expired WebUntis session for schools that sign in through their own
/// login page (Microsoft 365, Keycloak, IServ …), without showing anything.
/// The login page runs in an invisible web view with the same persistent cookie
/// store as `UntisWebLoginView`, so the school's own sign-in is usually still
/// remembered and WebUntis hands out a new session on its own. When the school
/// asks for the password again, this gives up and the student logs in visibly.
@MainActor
final class UntisSilentLogin: NSObject, WKNavigationDelegate {
    struct Session {
        let server: String
        let cookies: String
        let sessionID: String
    }

    private let webView: WKWebView
    private var hosts: [String]
    /// One renewal at a time (opening the app and the 30-minute refresh can meet).
    private static var running = false

    private init(server: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        hosts = [server.lowercased()]
        super.init()
        webView.navigationDelegate = self
    }

    /// A new session, or nil when the school wants an interactive login (or is offline).
    static func renew(server: String, loginName: String, ssoPath: String? = nil, timeout: Duration = .seconds(25)) async -> Session? {
        // The stored server can come from another device (Google Drive sync): only a plain host name
        // (no port, IP address or path) is loaded into the web view that holds the school's sign-in.
        guard untisIsValidHost(host: server.lowercased()) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = server
        components.path = "/WebUntis/"
        components.queryItems = [URLQueryItem(name: "school", value: loginName)]
        // The link the student tapped to reach the school's login, when it was learned: the start
        // page alone shows WebUntis' login form and never continues to the school's SSO.
        if let ssoPath, let start = Self.ssoURL(ssoPath, server: server) { components = start }
        // Web views load reliably only inside a window, which exists only in the foreground;
        // a background refresh leaves it to the next time the app opens.
        guard let url = components.url, !running, UIApplication.shared.applicationState == .active,
              let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else { return nil }
        running = true
        defer { running = false }
        let login = UntisSilentLogin(server: server)
        // It stays invisible and can't be touched.
        login.webView.alpha = 0
        login.webView.isUserInteractionEnabled = false
        window.insertSubview(login.webView, at: 0)
        defer { login.webView.removeFromSuperview() }
        login.webView.load(URLRequest(url: url))
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(1.5))
            if let session = await login.session() { return session }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Same rule as the visible login: only WebUntis hosts may become the server.
        guard let host = webView.url?.host?.lowercased(), Self.isWebUntisHost(host),
              !hosts.contains(host) else { return }
        hosts.append(host)
    }

    private func session() async -> Session? {
        let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        for host in hosts {
            guard let (header, sessionID) = Self.cookieHeader(for: host, in: all) else { continue }
            if await UntisClient(browserCookies: header).probeBrowserLogin(server: host, sessionID: sessionID).auth != nil {
                return Session(server: host, cookies: header, sessionID: sessionID)
            }
        }
        return nil
    }

    /// webuntis.com or one of its subdomains, as a plain host name.
    static func isWebUntisHost(_ host: String) -> Bool {
        (host == "webuntis.com" || host.hasSuffix(".webuntis.com")) && untisIsValidHost(host: host)
    }

    /// `path` as a URL on `server`, only when it stays a /WebUntis/ path on that host.
    static func ssoURL(_ path: String, server: String) -> URLComponents? {
        guard path.hasPrefix("/WebUntis/"), !path.contains("//"), !path.contains("\\"),
              let base = URL(string: "https://\(server)"), let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host()?.lowercased() == server.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components
    }

    /// Forgets the school login kept by the web views (WebUntis and the school's SSO), so
    /// after "WebUntis trennen" nobody else on this device is signed back in.
    static func forgetWebLogin() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    /// The web views keep the school login (cookies, website data) in Library/Cookies and
    /// Library/WebKit. Like the Keychain secret, it stays on this device: out of backups.
    static func keepWebLoginOutOfBackups() {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        for name in ["Cookies", "WebKit"] {
            var folder = library.appending(path: name, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
    }

    /// The `Cookie` header for `host` and its `JSESSIONID`, when there is a session.
    static func cookieHeader(for host: String, in cookies: [HTTPCookie]) -> (header: String, sessionID: String)? {
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
        guard let session = matching.first(where: { $0.name == "JSESSIONID" }) else { return nil }
        return (matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), session.value)
    }
}
