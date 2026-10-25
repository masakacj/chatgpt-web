import XCTest
import WebKit
@testable import ChatGPTWebOptimized

@MainActor
final class NativeResourceGateTests: XCTestCase {
    func testDefaultOffWithNoApprovedRules() {
        let name = "optimized.resource-test.(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let gate = NativeResourceGate(defaults: defaults)
        XCTAssertFalse(gate.isEnabled)
        XCTAssertEqual(NativeResourceGate.approvedRuleCount, 0)
        XCTAssertEqual(NativeResourceGate.approvedRulesJSON, "[]")
    }

    func testOptInIsPersistedButNoUnverifiedRuleIsApplied() {
        let name = "optimized.resource-test.(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let gate = NativeResourceGate(defaults: defaults)
        gate.isEnabled = true
        XCTAssertTrue(NativeResourceGate(defaults: defaults).isEnabled)
        var installed: Bool?
        gate.install(to: WKUserContentController(), safeMode: false) { installed = $0 }
        XCTAssertEqual(installed, false, "No approved rule may be installed")
    }

    func testSafeModeSkipsAndDisablesOptionalRules() {
        let name = "optimized.resource-test.(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let gate = NativeResourceGate(defaults: defaults)
        gate.isEnabled = true
        var installed: Bool?
        gate.install(to: WKUserContentController(), safeMode: true) { installed = $0 }
        XCTAssertEqual(installed, false)
        gate.disableForSafety()
        XCTAssertFalse(gate.isEnabled)
        XCTAssertFalse(NativeResourceGate(defaults: defaults).isEnabled)
    }
}
