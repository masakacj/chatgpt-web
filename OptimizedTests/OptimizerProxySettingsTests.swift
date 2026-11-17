import XCTest
import WebKit
@testable import ChatGPTWebOptimized

@MainActor
final class OptimizerProxySettingsTests: XCTestCase {
    private func endpoint(_ host: String = "server.proxy.example", port: Int = 443) -> OptimizerProxyEndpoint {
        OptimizerProxyEndpoint(host: host, port: port, username: "")
    }

    func testVisualOptimizerAdapterIsNotInjectedWhenBothOptionalFlagsAreOff() {
        let name = "optimizer-visual-script-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OptimizerProxySettings(defaults: defaults)
        let owner = ConversationManagerOwner()
        let handler = WeakOptimizedObservationHandler(owner: owner)

        let (minimal, proxyReady) = WebConfigurationFactory.make(
            owner: owner, handler: handler, pcHistoryEnabled: false,
            mcpOutputEnabled: false, proxySettings: settings)
        XCTAssertFalse(proxyReady, "Empty test proxy remains fail-closed")
        let minimalSources = minimal.userContentController.userScripts.map(\.source)
        XCTAssertEqual(minimalSources.count, 1, "CM observer must stay injected")
        XCTAssertTrue(minimalSources[0].contains("optimizedConversation"))
        XCTAssertTrue(minimalSources[0].contains("optimized-sidebar-touch-scroll"),
                      "Sidebar scrolling must share the CM user script, not add another script")
        XCTAssertFalse(minimalSources[0].contains("globalThis.__OPTIMIZED_PC_HISTORY_ENABLED__ ="))

        let (mcpOnly, _) = WebConfigurationFactory.make(
            owner: owner, handler: handler, pcHistoryEnabled: false,
            mcpOutputEnabled: true, proxySettings: settings)
        let mcpSources = mcpOnly.userContentController.userScripts.map(\.source)
        XCTAssertEqual(mcpSources.count, 2)
        XCTAssertTrue(mcpSources.contains {
            $0.contains("globalThis.__OPTIMIZED_PC_HISTORY_ENABLED__ = false;") &&
            $0.contains("globalThis.__OPTIMIZED_MCP_OUTPUT_RELIEF_ENABLED__ = true;")
        })
    }

    func testDefaultOfficeServerBackupAndNeverDirectWithoutEndpoints() {
        let name = "optimizer-proxy-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OptimizerProxySettings(defaults: defaults)
        XCTAssertEqual(settings.plan.mode, .officeServer)
        XCTAssertTrue(settings.plan.backupEnabled)
        XCTAssertTrue(settings.plan.denyDirect)
        XCTAssertFalse(settings.plan.ready)
        XCTAssertFalse(settings.canLoadWebView)
        // No implicit default configuration when the primary proxy is absent.
        XCTAssertFalse(settings.configure(WKWebsiteDataStore.nonPersistent()))
    }

    func testProxyOrderAndNoAutodirect() {
        var p = OptimizerProxyPlan()
        p.officeServer = endpoint()
        p.office = endpoint("office.proxy.example", port: 8443)
        XCTAssertTrue(p.ready)
        XCTAssertEqual(p.selected.map(\.host), ["server.proxy.example", "office.proxy.example"])
        p.mode = .office
        XCTAssertEqual(p.selected.map(\.host), ["office.proxy.example", "server.proxy.example"])
        p.mode = .direct
        XCTAssertEqual(p.selected.count, 0)
        // Direct requires explicit mode selection, never automatic failover.
        XCTAssertTrue(p.ready)
    }


    func testLegacyHomePlanIsMigratedWithoutEverUsingHomeExit() throws {
        let name = "optimizer-legacy-migration-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy: [String: Any] = [
            "mode": "home",
            "home": ["host": "old-home.invalid", "port": 18443, "username": "old-home"],
            "office": ["host": "gosto.781751.xyz", "port": 18444, "username": "office-user"],
            "backupEnabled": true, "denyDirect": true
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy),
                     forKey: "optimized.proxy.plan.v1")
        let migrated = OptimizerProxySettings(defaults: defaults)
        XCTAssertEqual(migrated.plan.mode, .officeServer)
        XCTAssertEqual(migrated.plan.officeServer.host, "gostos.781751.xyz")
        XCTAssertEqual(migrated.plan.officeServer.port, 18445)
        XCTAssertEqual(migrated.plan.office.host, "gosto.781751.xyz")
        XCTAssertFalse(migrated.plan.selected.map(\.host).contains("old-home.invalid"))
        XCTAssertNotNil(defaults.data(forKey: "optimized.proxy.plan.v1"),
                        "Legacy settings must be retained for rollback")
        XCTAssertNotNil(defaults.data(forKey: "optimized.proxy.plan.v2"))
        XCTAssertFalse(migrated.canLoadWebView,
                       "New OfficeServer credentials must be explicitly provisioned")
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
        plan.officeServer = endpoint()
        plan.office = endpoint("office.proxy.example", port: 8443)
        XCTAssertTrue(settings.apply(plan, officeServerPassword: "", officePassword: ""))
        let restored = OptimizerProxySettings(defaults: defaults)
        XCTAssertEqual(restored.plan, plan)
        XCTAssertTrue(restored.canLoadWebView)
        let serialized = String(decoding: defaults.data(forKey: "optimized.proxy.plan.v2")!, as: UTF8.self)
        XCTAssertFalse(serialized.contains("password"))
        XCTAssertFalse(serialized.contains("token"))
    }

    func testRouteChangeAfterWebViewCreatedRequiresNewAppProcess() {
        let name = "optimizer-proxy-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OptimizerProxySettings(defaults: defaults)
        var first = settings.plan
        first.officeServer = endpoint()
        first.office = endpoint("office.proxy.example", port: 8443)
        XCTAssertTrue(settings.apply(first, officeServerPassword: "", officePassword: ""))
        let store = WKWebsiteDataStore.nonPersistent()
        XCTAssertTrue(settings.configure(store))
        let oldCount = store.proxyConfigurations.count
        var new = first
        new.mode = .direct
        XCTAssertTrue(settings.apply(new, officeServerPassword: "", officePassword: ""))
        XCTAssertTrue(settings.pendingRestart)
        XCTAssertEqual(settings.plan, first, "Current process remains on original proxy")
        XCTAssertTrue(settings.configure(store))
        XCTAssertEqual(store.proxyConfigurations.count, oldCount,
                       "No in-process route reconfiguration, even after WebView rebuild")
        let relaunched = OptimizerProxySettings(defaults: defaults)
        XCTAssertEqual(relaunched.plan, new, "New process loads newly persisted choice")
    }

    func testConfiguredNativeProxiesDoNotAllowDirectFailover() {
        let name = "optimizer-proxy-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OptimizerProxySettings(defaults: defaults)
        var plan = settings.plan
        plan.officeServer = endpoint()
        plan.office = endpoint("office.proxy.example", port: 8443)
        XCTAssertTrue(settings.apply(plan, officeServerPassword: "", officePassword: ""))
        let store = WKWebsiteDataStore.nonPersistent()
        XCTAssertTrue(settings.configure(store))
        XCTAssertEqual(store.proxyConfigurations.count, 2)
        XCTAssertTrue(store.proxyConfigurations.allSatisfy { !$0.allowFailover })
    }
}
