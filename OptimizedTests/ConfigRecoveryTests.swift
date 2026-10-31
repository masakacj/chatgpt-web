import XCTest
@testable import ChatGPTWebOptimized

@MainActor
final class ConfigRecoveryTests: XCTestCase {
    func testRandomRecoveryKeyEncryptDecryptAndScopeIsolation() throws {
        let first = try XCTUnwrap(ConfigRecovery.generateKey())
        let second = try XCTUnwrap(ConfigRecovery.generateKey())
        XCTAssertEqual(first.count, 43)
        XCTAssertNotEqual(first, second)
        let original = Data("example local proxy config".utf8)
        let blob = try ConfigRecovery.encrypt(.optimizer, code: first, data: original)
        XCTAssertEqual(try ConfigRecovery.decrypt(.optimizer, code: first, blob: blob), original)
        XCTAssertThrowsError(try ConfigRecovery.decrypt(.mirror, code: first, blob: blob))
        XCTAssertThrowsError(try ConfigRecovery.decrypt(.optimizer, code: second, blob: blob))
        XCTAssertThrowsError(try ConfigRecovery.encrypt(.optimizer, code: "password", data: original))
    }

    func testProxyPlanCanExportAndRestoreWithoutInternetOrKeychainCredential() throws {
        let sourceSuite = "proxy-recovery-src-" + UUID().uuidString
        let destSuite = "proxy-recovery-dst-" + UUID().uuidString
        let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: sourceSuite))
        let destDefaults = try XCTUnwrap(UserDefaults(suiteName: destSuite))
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            destDefaults.removePersistentDomain(forName: destSuite)
        }
        let source = OptimizerProxySettings(defaults: sourceDefaults)
        var plan = OptimizerProxyPlan()
        plan.home = OptimizerProxyEndpoint(host: "proxy.home.example", port: 443, username: "")
        plan.office = OptimizerProxyEndpoint(host: "proxy.office.example", port: 8443, username: "")
        XCTAssertTrue(source.apply(plan, homePassword: "", officePassword: ""))
        let serialized = try XCTUnwrap(source.exportRecoveryConfig())

        let target = OptimizerProxySettings(defaults: destDefaults)
        XCTAssertTrue(target.importRecoveryConfig(serialized))
        XCTAssertEqual(target.plan, plan)
        XCTAssertTrue(target.canLoadWebView)
    }
}
