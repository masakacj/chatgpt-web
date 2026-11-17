import XCTest
@testable import ChatGPTWebOptimized

@MainActor
final class ConfigRecoveryTests: XCTestCase {
    func testSingleFixedEndpointAndAppScopedResponse() throws {
        XCTAssertEqual(ConfigRecovery.endpoint.absoluteString, "https://config.781751.xyz:58443")
        let plan: [String: Any] = [
            "mode": "home", "backupEnabled": false, "denyDirect": true,
            "home": ["host": "home.proxy.example", "port": 443, "username": ""],
            "office": ["host": "office.proxy.example", "port": 8443, "username": ""]
        ]
        let payload: [String: Any] = [
            "schema": 1, "app": "optimizer",
            "config": ["plan": plan, "homePassword": "", "officePassword": ""]
        ]
        let raw = try JSONSerialization.data(withJSONObject: payload)
        let config = try ConfigRecovery.parse(raw, scope: .optimizer)
        XCTAssertThrowsError(try ConfigRecovery.parse(raw, scope: .mirror))
        let source = "personal-config-test-src-" + UUID().uuidString
        let dest = "personal-config-test-dst-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: source))
        let restored = try XCTUnwrap(UserDefaults(suiteName: dest))
        defer {
            defaults.removePersistentDomain(forName: source)
            restored.removePersistentDomain(forName: dest)
        }
        let settings = OptimizerProxySettings(defaults: defaults)
        XCTAssertFalse(settings.importRecoveryConfig(config),
                       "Legacy Home config must not load without separate OfficeServer credentials")
        XCTAssertEqual(settings.plan.officeServer.host, "gostos.781751.xyz")
        XCTAssertFalse(settings.canLoadWebView)

        // New OfficeServer-only recovery never carries a Home endpoint.
        let v2 = try JSONSerialization.data(withJSONObject: [
            "plan": [
                "mode": "officeServer", "backupEnabled": false, "denyDirect": true,
                "officeServer": ["host": "gostos.781751.xyz", "port": 18445,
                                 "username": ""],
                "office": ["host": "office.proxy.example", "port": 8443,
                           "username": ""]
            ],
            "officeServerPassword": "", "officePassword": ""
        ])
        XCTAssertTrue(settings.importRecoveryConfig(v2))
        XCTAssertTrue(settings.canLoadWebView)
        XCTAssertEqual(settings.plan.officeServer.host, "gostos.781751.xyz")
        XCTAssertEqual(settings.plan.office.port, 8443)
        XCTAssertFalse(settings.plan.backupEnabled)
        let target = OptimizerProxySettings(defaults: restored)
        XCTAssertFalse(target.importRecoveryConfig(Data("invalid".utf8)))
        let explicitDirect: [String: Any] = [
            "plan": [
                "mode": "direct", "backupEnabled": false, "denyDirect": true,
                "home": ["host": "", "port": 0, "username": ""],
                "office": ["host": "", "port": 0, "username": ""]
            ],
            "homePassword": "", "officePassword": ""
        ]
        XCTAssertFalse(target.importRecoveryConfig(try JSONSerialization.data(withJSONObject: explicitDirect)))
        XCTAssertFalse(target.canLoadWebView)
    }

    func testRejectsMalformedOrOtherAppConfig() throws {
        let raw = try JSONSerialization.data(withJSONObject: [
            "schema": 1, "app": "mirror", "config": ["endpoint": "https://bridge.example"]
        ])
        XCTAssertThrowsError(try ConfigRecovery.parse(raw, scope: .optimizer))
        XCTAssertThrowsError(try ConfigRecovery.parse(Data("invalid".utf8), scope: .optimizer))
    }
}
