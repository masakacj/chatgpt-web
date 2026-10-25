import XCTest
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
}
