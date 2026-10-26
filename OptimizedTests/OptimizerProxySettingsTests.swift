import XCTest
import WebKit
@testable import ChatGPTWebOptimized

@MainActor
final class OptimizerProxySettingsTests: XCTestCase {
    private func endpoint(_ host: String = "home.proxy.example", port: Int = 443) -> OptimizerProxyEndpoint {
        OptimizerProxyEndpoint(host: host, port: port, username: "")
    }

    func testDefaultHomeBackupAndNeverDirectWithoutEndpoints() {
        let name = "optimizer-proxy-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OptimizerProxySettings(defaults: defaults)
        XCTAssertEqual(settings.plan.mode, .home)
        XCTAssertTrue(settings.plan.backupEnabled)
        XCTAssertTrue(settings.plan.denyDirect)
        XCTAssertFalse(settings.plan.ready)
        XCTAssertFalse(settings.canLoadWebView)
        // No implicit default configuration when the primary proxy is absent.
        XCTAssertFalse(settings.configure(WKWebsiteDataStore.nonPersistent()))
    }

    func testProxyOrderAndNoAutodirect() {
        var p = OptimizerProxyPlan()
        p.home = endpoint()
        p.office = endpoint("office.proxy.example", port: 8443)
        XCTAssertTrue(p.ready)
        XCTAssertEqual(p.selected.map(\.host), ["home.proxy.example", "office.proxy.example"])
        p.mode = .office
        XCTAssertEqual(p.selected.map(\.host), ["office.proxy.example", "home.proxy.example"])
        p.mode = .direct
        XCTAssertEqual(p.selected.count, 0)
        // Direct requires explicit mode selection, never automatic failover.
        XCTAssertTrue(p.ready)
    }

    func testMalformedEndpointsAreRejected() {
        var e = endpoint("https://unsafe.example", port: 443)
        XCTAssertFalse(e.valid)
        e = endpoint("x.example", port: 0)
        XCTAssertFalse(e.valid)
        e = endpoint("office.proxy.example", port: 65536)
        XCTAssertFalse(e.valid)
        e = endpoint("host.example/path", port: 443)
        XCTAssertFalse(e.valid)
        e = endpoint("safe.example", port: 8443)
        XCTAssertTrue(e.valid)
    }

    func testConfigPersistedNoCredentialsInUserDefaults() {
        let name = "optimizer-proxy-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OptimizerProxySettings(defaults: defaults)
        var plan = settings.plan
        plan.home = endpoint()
        plan.office = endpoint("office.proxy.example", port: 8443)
        XCTAssertTrue(settings.apply(plan, homePassword: "", officePassword: ""))
        let restored = OptimizerProxySettings(defaults: defaults)
        XCTAssertEqual(restored.plan, plan)
        XCTAssertTrue(restored.canLoadWebView)
        let serialized = String(decoding: defaults.data(forKey: "optimized.proxy.plan.v1")!, as: UTF8.self)
        XCTAssertFalse(serialized.contains("password"))
        XCTAssertFalse(serialized.contains("token"))
    }

    func testBackupIsOneShotAndNeverBecomesDirect() {
        let defaults = UserDefaults(suiteName: "optimizer-proxy-" + UUID().uuidString)!
        var plan = OptimizerProxyPlan()
        plan.home = endpoint()
        plan.office = endpoint("office.proxy.example", port: 8443)
        let settings = OptimizerProxySettings(defaults: defaults)
        XCTAssertTrue(settings.apply(plan, homePassword: "", officePassword: ""))
        XCTAssertTrue(settings.selectBackupForInitialLoad())
        XCTAssertTrue(settings.activeBackup)
        XCTAssertFalse(settings.selectBackupForInitialLoad())
        XCTAssertEqual(settings.plan.mode, .home, "Saved choice remains Home")
        plan.backupEnabled = false
        XCTAssertTrue(settings.apply(plan, homePassword: "", officePassword: ""))
        XCTAssertFalse(settings.selectBackupForInitialLoad())
    }

    func testConfiguredNativeProxiesDoNotAllowDirectFailover() {
        let name = "optimizer-proxy-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OptimizerProxySettings(defaults: defaults)
        var plan = settings.plan
        plan.home = endpoint()
        plan.office = endpoint("office.proxy.example", port: 8443)
        XCTAssertTrue(settings.apply(plan, homePassword: "", officePassword: ""))
        let store = WKWebsiteDataStore.nonPersistent()
        XCTAssertTrue(settings.configure(store))
        XCTAssertEqual(store.proxyConfigurations.count, 2)
        XCTAssertTrue(store.proxyConfigurations.allSatisfy { !$0.allowFailover })
    }
}
