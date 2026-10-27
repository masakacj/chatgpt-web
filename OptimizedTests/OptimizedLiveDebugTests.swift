import XCTest
import WebKit
@testable import ChatGPTWebOptimized

@MainActor
final class OptimizedLiveDebugTests: XCTestCase {
    func testPairingIsPersistentAndLiveDebugDefaultsOff() {
        let defaults = UserDefaults(suiteName: "optimized-live-test-" + UUID().uuidString)!
        let first = OptimizedLiveDebug(defaults: defaults)
        XCTAssertFalse(first.isEnabled)
        XCTAssertTrue(first.room.hasPrefix("ios_"))
        let pairing = first.pairingCode
        XCTAssertFalse(pairing.isEmpty)
        let second = OptimizedLiveDebug(defaults: defaults)
        XCTAssertEqual(pairing, second.pairingCode)
        XCTAssertFalse(second.isEnabled)
    }

    func testEnablingCanBeDisabledWithoutPage() {
        let defaults = UserDefaults(suiteName: "optimized-live-test-" + UUID().uuidString)!
        let probe = OptimizedLiveDebug(defaults: defaults)
        probe.setForeground(false)
        probe.isEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "optimized.liveDebug.enabled.v1"))
        probe.isEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "optimized.liveDebug.enabled.v1"))
    }

    func testBackgroundAndDetachStopPolling() {
        let defaults = UserDefaults(suiteName: "optimized-live-test-" + UUID().uuidString)!
        let probe = OptimizedLiveDebug(defaults: defaults)
        probe.isEnabled = true

        // Background transition immediately stops polling loop
        probe.setForeground(false)
        XCTAssertEqual(probe.state, "后台暂停")

        // Foreground resumes polling
        probe.setForeground(true)

        // Detaching WKWebView cancels/stops polling
        let webView = WKWebView(frame: .zero)
        probe.attach(webView)
        XCTAssertNotNil(probe.webView)

        probe.detach(webView)
        XCTAssertNil(probe.webView)
        XCTAssertEqual(probe.state, "网页未就绪暂停")
    }

    func testIdlePollThrottlesAndSwitchesOnActivePeriod() {
        let defaults = UserDefaults(suiteName: "optimized-live-test-" + UUID().uuidString)!
        let probe = OptimizedLiveDebug(defaults: defaults)
        probe.isEnabled = true

        // Idle polling is throttled (20s, within 15-30s range)
        XCTAssertEqual(probe.pollInterval, 20.0)

        // Snapshot request briefly accelerates to 3s active response window
        probe.activateActiveIntervalForTesting(seconds: 60)
        XCTAssertEqual(probe.pollInterval, 3.0)

        // Disabling or stopping immediately resets active period back to idle interval
        probe.stop()
        XCTAssertEqual(probe.pollInterval, 20.0)
    }

    func testReadOnlyThermalEvidenceReportsNominalWithoutCelsius() {
        let current = ProcessInfo.processInfo.thermalState
        let formatted = OptimizedRootView.formatThermalState(current)
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertFalse(formatted.contains("℃"))
        XCTAssertFalse(formatted.contains("Celsius"))
        XCTAssertFalse(formatted.contains("度"))

        let teleLabel = OptimizedTelemetry.thermalStateString(current)
        XCTAssertFalse(teleLabel.isEmpty)
        XCTAssertFalse(teleLabel.contains("℃"))
        XCTAssertFalse(teleLabel.contains("Celsius"))
    }

    func testSafeModeStopsLiveDebugPolling() {
        let defaults = UserDefaults(suiteName: "optimized-live-test-" + UUID().uuidString)!
        let probe = OptimizedLiveDebug(defaults: defaults)
        let supervisor = NativeOptimizationSupervisor(defaults: defaults)
        probe.supervisor = supervisor
        probe.isEnabled = true

        supervisor.recordWebContentTermination(route: "conversation", isSynthetic: false)
        XCTAssertTrue(supervisor.isSafeModeActive)

        probe.stop()
        XCTAssertEqual(probe.state, "安全模式暂停")
    }

    func testSafeRouteSanitizesThermalRoutes() {
        XCTAssertEqual(OptimizedTelemetry.safeRoute("thermal_privateToken"), "other")
        XCTAssertEqual(OptimizedTelemetry.safeRoute("thermal_nominal"), "thermal_nominal")
        XCTAssertEqual(OptimizedTelemetry.safeRoute("thermal_fair"), "thermal_fair")
        XCTAssertEqual(OptimizedTelemetry.safeRoute("thermal_serious"), "thermal_serious")
        XCTAssertEqual(OptimizedTelemetry.safeRoute("thermal_critical"), "thermal_critical")
        XCTAssertEqual(OptimizedTelemetry.safeRoute("thermal_unknown"), "other")
    }
}
