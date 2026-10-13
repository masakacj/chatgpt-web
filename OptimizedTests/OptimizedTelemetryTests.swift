import XCTest
@testable import ChatGPTWebOptimized

@MainActor
final class OptimizedTelemetryTests: XCTestCase {
    func testRouteAllowsOnlyCategoriesAndIntegerErrorCodes() {
        XCTAssertEqual(OptimizedTelemetry.safeRoute("conversation"), "conversation")
        XCTAssertEqual(OptimizedTelemetry.safeRoute("project", errorCode: -1009),
                       "project_e-1009")
        XCTAssertEqual(OptimizedTelemetry.safeRoute("https://chatgpt.com/c/private-id"),
                       "other")
        XCTAssertEqual(OptimizedTelemetry.safeRoute("cookie=private;token=secret"),
                       "other")
        XCTAssertLessThanOrEqual(
            OptimizedTelemetry.safeRoute("conversation", errorCode: Int.max).count, 24
        )
    }

    func testOptedOutRecorderDoesNotQueueOrSendEvents() {
        let suite = "optimized-telemetry-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("UserDefaults suite unavailable")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "optimized.telemetry.enabled.v1")
        let recorder = OptimizedTelemetry(defaults: defaults)
        XCTAssertFalse(recorder.isEnabled)
        recorder.record(.contentTerminated, route: "conversation", urgent: true)
        XCTAssertEqual(recorder.pendingCount, 0)
        XCTAssertEqual(recorder.state, "已关闭")
        XCTAssertTrue(recorder.sessionId.hasPrefix("s_"))
        XCTAssertTrue(recorder.installId.hasPrefix("ios_"))
    }

    func testLocalReportContainsNoWebpageContent() {
        let suite = "optimized-telemetry-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("UserDefaults suite unavailable")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "optimized.telemetry.enabled.v1")
        let recorder = OptimizedTelemetry(defaults: defaults)
        let text = recorder.localReport
        XCTAssertTrue(text.contains("会话:"))
        XCTAssertTrue(text.contains("关闭"))
        XCTAssertFalse(text.contains("https://chatgpt.com/c/"))
    }
}
