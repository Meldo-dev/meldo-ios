import MeldeCore
import SwiftUI
import WebKit

/// The school's own WebUntis login page inside Meldo, for schools that sign in
/// through Microsoft 365, IServ or another login (SSO). The student logs in on
/// those pages; Meldo only reads the resulting WebUntis session cookie and asks
/// WebUntis who is logged in. Passwords typed here never reach Meldo.
struct UntisWebLoginView: View {
    let school: FfiUntisSchool
    /// Called once WebUntis confirms the login: the WebUntis host the session
    /// belongs to, the `Cookie` header, the session id and the WebUntis link that led
    /// to the school's login (for the background renewal), if one was seen.
    var onLoggedIn: (_ server: String, _ cookies: String, _ sessionID: String, _ ssoPath: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var watcher = UntisLoginWatcher()

    var body: some View {
        NavigationStack {
            UntisWebView(school: school, watcher: watcher)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
                        Label(watcher.status, systemImage: watcher.checking ? "hourglass" : "person.badge.key")
                            .font(.footnote.weight(.semibold))
                        if let failure = watcher.loadFailure {
                            // A login page that can't load would otherwise sit on "Weiterleitung…" forever.
                            HStack(alignment: .firstTextBaseline) {
                                Label(failure, systemImage: "wifi.exclamationmark")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button(L("Erneut versuchen")) { watcher.retry() }
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                        if let detail = watcher.detail {
                            Text(detail)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, DS.spacingS)
                    .background(.bar)
                }
                .navigationTitle(school.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Abbrechen")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Ich bin angemeldet")) {
                            Task { await watcher.check(manual: true) }
                        }
                        .disabled(watcher.checking)
                    }
                }
        }
        .onAppear { watcher.onLoggedIn = onLoggedIn }
        .onDisappear {
            watcher.stop()
            // The school login may have left cookies even if connecting failed or the sheet was
            // closed: they stay out of backups right away, not only after the next launch.
            UntisSilentLogin.keepWebLoginOutOfBackups()
        }
    }
}

/// Watches the web view's cookies and asks WebUntis whether the student is
/// logged in. Checks every WebUntis host the page has visited, because after
/// a school login WebUntis may land on another server than the search said.
@Observable
final class UntisLoginWatcher {
    var status = L("Melde dich so an, wie du es von WebUntis kennst, z. B. mit Microsoft 365. Meldo erkennt die Anmeldung automatisch.")
    var detail: String?
    var checking = false
    /// Why the current page didn't load (host and reason), shown with a retry button.
    var loadFailure: String?
    @ObservationIgnored private var failedURL: URL?

    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored var school: FfiUntisSchool?
    @ObservationIgnored var onLoggedIn: ((String, String, String, String?) -> Void)?
    /// The last WebUntis page requested, and the one that led away to the school's login.
    @ObservationIgnored private var lastUntisURL: URL?
    @ObservationIgnored private(set) var ssoPath: String?
    @ObservationIgnored private var hosts: [String] = []
    @ObservationIgnored private var lastChecked: [String: String] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var done = false

    func start(school: FfiUntisSchool) {
        self.school = school
        // The server from the school search is trusted as-is (some schools host WebUntis themselves).
        hosts = [school.server.lowercased()]
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.check(manual: false)
            }
        }
    }

    /// Also stops a check that is still waiting for WebUntis from reporting a login.
    func stop() {
        done = true
        task?.cancel()
    }

    func pageFailed(_ error: any Error, webView: WKWebView) {
        let nsError = error as NSError
        // Cancelled loads and policy interruptions are part of normal redirects.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        failedURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url
        let host = failedURL?.host() ?? L("Die Anmeldeseite")
        loadFailure = L("\(host) ist gerade nicht erreichbar.")
    }

    func pageLoaded() {
        loadFailure = nil
        failedURL = nil
    }

    func retry() {
        loadFailure = nil
        if let failedURL { webView?.load(URLRequest(url: failedURL)) } else { webView?.reload() }
    }

    /// Learns which WebUntis link starts the school login: the last WebUntis request
    /// before the page leaves for another host (Microsoft, the school's SSO).
    func navigating(to url: URL?) {
        guard let url, let host = url.host()?.lowercased() else { return }
        if hosts.contains(host) || host == "webuntis.com" || host.hasSuffix(".webuntis.com") {
            lastUntisURL = url
        } else if ssoPath == nil, let start = lastUntisURL, start.path() != "/WebUntis/", start.path() != "/WebUntis",
                  start.path().hasPrefix("/WebUntis/") {
            ssoPath = start.path() + (start.query().map { "?" + $0 } ?? "")
        }
    }

    func remember(host: String?) {
        // Only real WebUntis hosts: "webuntis.evil.example" must not become the school's server.
        guard let host = host?.lowercased(), host == "webuntis.com" || host.hasSuffix(".webuntis.com"),
              !hosts.contains(host) else { return }
        hosts.append(host)
    }

    /// `manual`: the student says they are logged in; check every host now and
    /// show what WebUntis answered if it still fails.
    func check(manual: Bool) async {
        guard !done, !checking, let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        remember(host: webView?.url?.host)
        let all = await store.allCookies()
        if manual {
            checking = true
            status = L("Prüfe die Anmeldung …")
        }
        defer { if manual { checking = false } }
        var report: [String] = []
        for host in hosts {
            guard let (header, sessionID) = UntisSilentLogin.cookieHeader(for: host, in: all) else {
                report.append("\(host): " + L("noch keine Sitzung"))
                continue
            }
            // Automatic checks only ask WebUntis again when the cookies changed.
            if !manual, lastChecked[host] == header { continue }
            lastChecked[host] = header
            let probe = await UntisClient(browserCookies: header).probeBrowserLogin(server: host, sessionID: sessionID)
            if probe.auth != nil, !done {
                stop()
                status = L("Angemeldet. Stundenplan wird geladen …")
                onLoggedIn?(host, header, sessionID, ssoPath)
                return
            }
            report.append(probe.detail)
        }
        if manual {
            status = L("Meldo erkennt die Anmeldung noch nicht. Das hat WebUntis geantwortet:")
            detail = report.joined(separator: "\n")
        }
    }
}

private struct UntisWebView: UIViewRepresentable {
    let school: FfiUntisSchool
    let watcher: UntisLoginWatcher

    func makeCoordinator() -> Coordinator { Coordinator(watcher: watcher) }

    func makeUIView(context: Context) -> WKWebView {
        // The default data store keeps the Microsoft sign-in, so logging in again
        // after the WebUntis session ran out is usually one tap.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        watcher.webView = view
        var components = URLComponents()
        components.scheme = "https"
        components.host = school.server
        components.path = "/WebUntis/"
        components.queryItems = [URLQueryItem(name: "school", value: school.loginName)]
        if let url = components.url { view.load(URLRequest(url: url)) }
        watcher.start(school: school)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.watcher.stop()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let watcher: UntisLoginWatcher

        init(watcher: UntisLoginWatcher) {
            self.watcher = watcher
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            watcher.pageFailed(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            watcher.pageFailed(error, webView: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.targetFrame?.isMainFrame ?? true { watcher.navigating(to: navigationAction.request.url) }
            return .allow
        }

        /// Login pages that open a new window (target=_blank, window.open) continue in this one.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            watcher.pageLoaded()
            watcher.remember(host: webView.url?.host)
            Task { await watcher.check(manual: false) }
        }
    }
}
