import XCTest
import WebKit
@testable import ChatGPTWebOptimized

@MainActor
final class NativeResourceGateTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "optimized.resource-test.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { value.removePersistentDomain(forName: name) }
        return value
    }

    func testNewRuleRevisionDefaultsOffAndExplicitOptInPersists() throws {
        let settings = defaults()
        settings.set(true, forKey: "optimized.resourceGate.enabled.v1") // Previous ON is quarantined.
        let gate = NativeResourceGate(defaults: settings)
        XCTAssertFalse(gate.isEnabled)
        XCTAssertEqual(gate.appliedRuleCount, 0)
        gate.isEnabled = true
        XCTAssertTrue(NativeResourceGate(defaults: settings).isEnabled)
        gate.isEnabled = false
        XCTAssertFalse(NativeResourceGate(defaults: settings).isEnabled)

        let data = try XCTUnwrap(NativeResourceGate.approvedRulesJSON.data(using: .utf8))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rules.count, NativeResourceGate.approvedRuleCount)
        for rule in rules {
            let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
            XCTAssertEqual(rule["action"] as? [String: String], ["type": "block"])
            XCTAssertEqual(trigger["if-domain"] as? [String], ["chatgpt.com", "*chatgpt.com"])
            XCTAssertEqual(trigger["load-type"] as? [String], ["third-party"])
            let types = try XCTUnwrap(trigger["resource-type"] as? [String])
            XCTAssertEqual(types, ["script", "image", "raw"])
            XCTAssertFalse(types.contains("document"))
            XCTAssertFalse(types.contains("websocket"))
            let pattern = try XCTUnwrap(trigger["url-filter"] as? String)
            let regex = try NSRegularExpression(pattern: pattern)
            for critical in [
                "https://chatgpt.com/backend-api/conversation",
                "https://auth.openai.com/api/auth/session",
                "https://files.oaiusercontent.com/attachment",
                "https://cdn.oaistatic.com/assets/chat.js",
                "https://chatgpt.com/g/project/c/conversation"
            ] {
                XCTAssertNil(regex.firstMatch(in: critical, range: NSRange(critical.startIndex..., in: critical)))
            }
        }
    }

    func testTrackerPatternsMatchOnlyNarrowThirdPartyResources() throws {
        let data = try XCTUnwrap(NativeResourceGate.approvedRulesJSON.data(using: .utf8))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let positives = [
            "https://www.google-analytics.com/g/collect?v=2",
            "https://www.google-analytics.com/collect?v=1",
            "https://stats.doubleclick.net/pagead/conversion",
            "https://stats.doubleclick.net/activityi/123",
            "https://www.googletagmanager.com/gtm.js?id=GTM-123",
            "https://www.clarity.ms/collect?cid=1",
            "https://www.clarity.ms/tag/abc123"
        ]
        for (rule, candidate) in zip(rules, positives) {
            let pattern = try XCTUnwrap((rule["trigger"] as? [String: Any])?["url-filter"] as? String)
            let regex = try NSRegularExpression(pattern: pattern)
            XCTAssertNotNil(regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)))
        }
    }

    func testApprovedRulesCompileAndInstallInWebKit() async {
        let gate = NativeResourceGate(defaults: defaults())
        gate.isEnabled = true
        let controller = WKUserContentController()
        let installed = expectation(description: "WebKit content blocker compiled")
        gate.install(to: controller, safeMode: false) { success in
            XCTAssertTrue(success, "WebKit must accept the exact release JSON rules")
            installed.fulfill()
        }
        await fulfillment(of: [installed], timeout: 18)
        XCTAssertEqual(gate.appliedRuleCount, NativeResourceGate.approvedRuleCount)
    }

    func testSafeModeAndSavedOptOutNeverInstallRules() {
        let gate = NativeResourceGate(defaults: defaults())
        gate.isEnabled = true
        var installed: Bool?
        gate.install(to: WKUserContentController(), safeMode: true) { installed = $0 }
        XCTAssertEqual(installed, false)
        XCTAssertEqual(gate.appliedRuleCount, 0)

        gate.disableForSafety()
        XCTAssertFalse(gate.isEnabled)
        gate.install(to: WKUserContentController(), safeMode: false) { installed = $0 }
        XCTAssertEqual(installed, false)
    }
}
