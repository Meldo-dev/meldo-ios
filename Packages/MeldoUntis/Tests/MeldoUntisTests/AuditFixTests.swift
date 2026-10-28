import Foundation
import MeldeCore
import MeldoKit
import MeldoState
import Testing
@testable import MeldoUntis

/// Regression tests for findings from earlier security reviews.
@Suite("Audit fixes")
struct AuditFixTests {
    func request(_ url: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = method
        r.setValue("JSESSIONID=1", forHTTPHeaderField: "Cookie")
        r.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        return r
    }

    @Test func passwordLoginNeverFollowsToAnotherHost() {
        let login = request("https://school.webuntis.com/WebUntis/jsonrpc.do", method: "POST")
        #expect(UntisRedirectGuard.follow(from: login, to: request("https://other.example.com/x", method: "POST")) == nil)
        #expect(UntisRedirectGuard.follow(from: login, to: request("https://other.example.com/x")) == nil)
        // Same host stays allowed (e.g. a path change on the school server).
        #expect(UntisRedirectGuard.follow(from: login, to: request("https://school.webuntis.com/y", method: "POST")) != nil)
    }

    @Test func getRedirectsAreValidatedAndStripped() {
        let get = request("https://school.webuntis.com/WebUntis/api/x")
        #expect(UntisRedirectGuard.follow(from: get, to: request("http://school.webuntis.com/x")) == nil)
        #expect(UntisRedirectGuard.follow(from: get, to: request("https://localhost/x")) == nil)
        let moved = UntisRedirectGuard.follow(from: get, to: request("https://other.webuntis.com/x"))
        #expect(moved != nil)
        #expect(moved?.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(moved?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - Run 2

    @Test func anotherPortIsAnotherServer() {
        let login = request("https://school.webuntis.com/WebUntis/jsonrpc.do", method: "POST")
        #expect(UntisRedirectGuard.follow(from: login, to: request("https://school.webuntis.com:8443/x", method: "POST")) == nil)
        let get = request("https://school.webuntis.com/WebUntis/api/x")
        #expect(UntisRedirectGuard.follow(from: get, to: request("https://school.webuntis.com:8443/x")) == nil)
        // An explicit :443 is the same server.
        #expect(UntisRedirectGuard.follow(from: get, to: request("https://school.webuntis.com:443/y")) != nil)
    }

    @Test(arguments: ["10.0.0.1", "192.168.178.1", "0x7f.1", "0x7f.0x1", "127.1"])
    func ipAddressesAreNoServers(host: String) {
        #expect(!untisIsValidHost(host: host))
    }

    @Test func secretKeysOfDifferentAccountsNeverMatch() {
        let a = UntisLink(server: "s.webuntis.com", loginName: "a|b", schoolName: "", user: "c")
        let b = UntisLink(server: "s.webuntis.com", loginName: "a", schoolName: "", user: "b|c")
        #expect(AppModel.keychainAccount(a) != AppModel.keychainAccount(b))
        // Plain names keep their old key, so nobody has to log in again.
        let plain = UntisLink(server: "s.webuntis.com", loginName: "gym-koeln", schoolName: "", user: "max")
        #expect(AppModel.keychainAccount(plain) == "s.webuntis.com|gym-koeln|max")
        // "%" alone keeps the old key too, and can't imitate an escaped name.
        let percent = UntisLink(server: "s.webuntis.com", loginName: "a%7Cb", schoolName: "", user: "c")
        #expect(AppModel.keychainAccount(percent) == "s.webuntis.com|a%7Cb|c")
        #expect(AppModel.keychainAccount(percent) != AppModel.keychainAccount(a))
    }

    /// A restored backup brings the link and the web views' cookies, but not this
    /// device's Keychain secret: the school login must be done again, never replayed.
    @MainActor @Test func schoolLoginWithoutSecretOnThisDeviceAsksToLogIn() async {
        let model = AppModel(store: nil)
        let link = UntisLink(server: "restored-\(UUID().uuidString.prefix(8).lowercased()).webuntis.com",
                             loginName: "x", schoolName: "", user: "", browserLogin: true)
        model.mutate { $0.untis = link }
        await #expect(throws: UntisClient.Failure.sessionExpired) { try await model.refreshUntis() }
    }

    @MainActor @Test func disconnectStopsRunningImports() {
        let model = AppModel(store: nil)
        let untis = model.untisGeneration
        model.mutate { $0.untis = UntisLink(server: "s.webuntis.com", loginName: "x", schoolName: "", user: "y") }
        model.disconnectUntis()
        #expect(model.untisGeneration == untis + 1)
    }
}
