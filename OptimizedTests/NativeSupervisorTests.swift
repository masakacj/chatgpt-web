import XCTest
@testable import ChatGPTWebOptimized

@MainActor
final class NativeSupervisorTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.optimized.supervisor.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testNormalLaunchAndCleanLifecycle() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        supervisor.recordLaunch()

        XCTAssertFalse(supervisor.isSafeModeActive, "Fresh launch should not activate safe mode")
        XCTAssertFalse(supervisor.isCircuitOpen, "Fresh launch should keep circuit breaker closed")
        XCTAssertEqual(supervisor.verifiedTerminationCount, 0, "No verified terminations on fresh launch")
        XCTAssertTrue(testDefaults.bool(forKey: NativeOptimizationSupervisor.sessionActiveKey))

        supervisor.recordForeground()
        XCTAssertTrue(testDefaults.bool(forKey: NativeOptimizationSupervisor.sessionActiveKey))

        supervisor.recordBackground()
        // Clean background should clear active session flag
        XCTAssertFalse(testDefaults.bool(forKey: NativeOptimizationSupervisor.sessionActiveKey),
                       "Background transition must clear active session marker so it is not treated as unclean crash")
        XCTAssertFalse(supervisor.isSafeModeActive)
    }

    func testVerifiedTerminationDoesNotAutoRebuildWebView() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        let model = OptimizedAppModel()
        model.supervisor = supervisor

        let initialGeneration = model.webViewGeneration
        XCTAssertFalse(model.processTerminated)

        // WebContent process termination occurs
        model.markProcessTerminated(route: "conversation", isSynthetic: false)

        XCTAssertTrue(model.processTerminated, "Process termination must set processTerminated")
        XCTAssertTrue(supervisor.isSafeModeActive, "Process termination must activate native safe mode")
        XCTAssertEqual(supervisor.verifiedTerminationCount, 1, "Verified termination count must be 1")
        XCTAssertFalse(supervisor.isCircuitOpen, "Single termination must not open circuit breaker (threshold is 2)")

        // CRITICAL INVARIANT: NEVER automatically regenerate WKWebView!
        XCTAssertEqual(model.webViewGeneration, initialGeneration,
                       "WebView generation must NOT change automatically on termination; must await explicit user confirmation")
    }

    func testCircuitBreakerOpensAfterTwoTerminationsInTenMinutes() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        supervisor.recordLaunch()

        // 1st verified termination
        supervisor.recordWebContentTermination(route: "conversation", isSynthetic: false)
        XCTAssertTrue(supervisor.isSafeModeActive)
        XCTAssertFalse(supervisor.isCircuitOpen, "1st termination should not open circuit")
        XCTAssertEqual(supervisor.verifiedTerminationCount, 1)

        // User confirms rebuild once
        supervisor.confirmRebuild()
        XCTAssertFalse(supervisor.isSafeModeActive)
        XCTAssertFalse(supervisor.isCircuitOpen)

        // 2nd verified termination within 10 minutes
        supervisor.recordWebContentTermination(route: "conversation", isSynthetic: false)
        XCTAssertTrue(supervisor.isSafeModeActive)
        XCTAssertTrue(supervisor.isCircuitOpen, "2nd verified termination within 10 minutes MUST open circuit breaker")
        XCTAssertEqual(supervisor.verifiedTerminationCount, 2)
        XCTAssertTrue(testDefaults.bool(forKey: NativeOptimizationSupervisor.circuitOpenKey),
                      "Circuit open state must be persisted in UserDefaults")
    }

    func testOpenCircuitPersistsAcrossRestartAndEnforcesSafeMode() {
        // Session 1: Cause circuit to open
        let session1 = NativeOptimizationSupervisor(defaults: testDefaults)
        session1.recordLaunch()
        session1.recordWebContentTermination(route: "conversation", isSynthetic: false)
        session1.recordWebContentTermination(route: "conversation", isSynthetic: false)
        XCTAssertTrue(session1.isCircuitOpen)

        // Session 2: App restart
        let session2 = NativeOptimizationSupervisor(defaults: testDefaults)
        XCTAssertTrue(session2.isCircuitOpen, "Persisted circuit state must be open on restart")
        XCTAssertTrue(session2.isSafeModeActive, "Persisted circuit must establish isSafeModeActive synchronously upon init before recordLaunch or UI creation")

        let model = OptimizedAppModel()
        _ = OptimizedRootView(supervisor: session2, model: model)
        XCTAssertTrue(model.processTerminated, "Model processTerminated must be set synchronously when circuit is open at initialization")

        session2.recordLaunch()
        XCTAssertTrue(session2.isSafeModeActive, "App launch with open circuit must immediately enter safe mode")
        XCTAssertTrue(session2.isCircuitOpen)
    }

    func testConfirmedRecoverySurvivesRelaunchWithoutNewTermination() {
        let first = NativeOptimizationSupervisor(defaults: testDefaults)
        first.recordLaunch()
        first.recordWebContentTermination(route: "project")
        first.recordWebContentTermination(route: "project")
        XCTAssertTrue(first.isCircuitOpen)

        first.confirmRebuild()
        XCTAssertFalse(first.isCircuitOpen)

        let restarted = NativeOptimizationSupervisor(defaults: testDefaults)
        restarted.recordLaunch()
        XCTAssertEqual(restarted.verifiedTerminationCount, 2)
        XCTAssertFalse(restarted.isCircuitOpen, "Acknowledged historical exits cannot reopen the circuit on launch")
        XCTAssertFalse(restarted.isSafeModeActive)

        restarted.recordWebContentTermination(route: "project")
        XCTAssertTrue(restarted.isCircuitOpen, "A new verified exit must reapply the circuit threshold")
    }

    func testSyntheticTerminationDoesNotPoisonCircuitBreaker() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        supervisor.recordLaunch()

        // User initiates simulated WebContent termination fixture from diagnostics
        supervisor.recordWebContentTermination(route: "home", isSynthetic: true)

        XCTAssertTrue(supervisor.isSafeModeActive, "Simulated termination must exercise safe mode screen")
        XCTAssertEqual(supervisor.verifiedTerminationCount, 0,
                       "Simulated termination must NOT count towards verified hardware terminations")
        XCTAssertFalse(supervisor.isCircuitOpen)

        // Repeated simulated terminations must not open the circuit
        supervisor.recordWebContentTermination(route: "home", isSynthetic: true)
        XCTAssertFalse(supervisor.isCircuitOpen, "Simulated terminations must not open circuit breaker")
        XCTAssertEqual(supervisor.verifiedTerminationCount, 0)

        // Check journal entry properties
        let lastEntry = supervisor.journal.last
        XCTAssertNotNil(lastEntry)
        XCTAssertEqual(lastEntry?.kind, "simulated_termination")
        XCTAssertFalse(lastEntry?.isVerified ?? true)
    }

    func testUnknownShutdownDoesNotClaimOOMOrJetsam() {
        // Simulate previous session death without clean background
        testDefaults.set(true, forKey: NativeOptimizationSupervisor.sessionActiveKey)

        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        supervisor.recordLaunch()

        // Journal should contain unknown_shutdown
        let unknownEntry = supervisor.journal.first { $0.kind == "unknown_shutdown" }
        XCTAssertNotNil(unknownEntry, "Unclean exit must be logged as unknown_shutdown")

        // Invariant: after an unknown whole-app death do NOT claim jetsam/OOM proven
        for entry in supervisor.journal {
            let lowerKind = entry.kind.lowercased()
            XCTAssertFalse(lowerKind.contains("oom"), "Must not falsely claim OOM")
            XCTAssertFalse(lowerKind.contains("jetsam"), "Must not falsely claim jetsam")
        }

        if let reason = supervisor.lastFailureReason?.lowercased() {
            XCTAssertFalse(reason.contains("oom"), "Failure reason must not claim OOM")
            XCTAssertFalse(reason.contains("jetsam"), "Failure reason must not claim jetsam")
        }
    }

    func testRepeatedUnknownAppExitsUseNativeSafeModeWithoutClaimingWebContentCrash() {
        let first = NativeOptimizationSupervisor(defaults: testDefaults)
        first.recordLaunch()
        let second = NativeOptimizationSupervisor(defaults: testDefaults)
        second.recordLaunch()
        XCTAssertFalse(second.isSafeModeActive, "A single force-quit must not force safe mode")

        let third = NativeOptimizationSupervisor(defaults: testDefaults)
        third.recordLaunch()
        XCTAssertTrue(third.isSafeModeActive, "Two unclean launches must prevent another automatic WebView creation")
        XCTAssertFalse(third.isCircuitOpen, "Unknown app exits are not verified WebContent terminations")
        XCTAssertEqual(third.verifiedTerminationCount, 0)
        XCTAssertTrue(third.lastFailureReason?.contains("原因尚未确认") == true)
        third.confirmRebuild()
        XCTAssertFalse(third.isSafeModeActive, "User may explicitly choose to retry")
    }

    func testCleanBackgroundBreaksUnknownShutdownSequence() {
        let first = NativeOptimizationSupervisor(defaults: testDefaults)
        first.recordLaunch()
        let second = NativeOptimizationSupervisor(defaults: testDefaults)
        second.recordLaunch()
        second.recordBackground()
        let third = NativeOptimizationSupervisor(defaults: testDefaults)
        third.recordLaunch()
        third.recordLaunch()
        XCTAssertFalse(third.isSafeModeActive, "A clean background breaks the repeated-unclean streak")
    }

    func testUserConfirmedRebuildRestoresHomeRouteAndGeneratesNewWebView() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        let model = OptimizedAppModel()
        model.supervisor = supervisor

        let initialGen = model.webViewGeneration
        model.targetURL = URL(string: "https://chatgpt.com/c/problematic-chat-session")!

        model.markProcessTerminated(route: "conversation", isSynthetic: false)
        XCTAssertTrue(model.processTerminated)
        XCTAssertTrue(supervisor.isSafeModeActive)

        // User explicitly confirms rebuild
        model.rebuildAfterConfirmation()

        XCTAssertFalse(model.processTerminated)
        XCTAssertFalse(supervisor.isSafeModeActive)
        XCTAssertNotEqual(model.webViewGeneration, initialGen,
                          "Confirmed rebuild must generate a new webView generation UUID")
        XCTAssertEqual(model.targetURL.absoluteString, "https://chatgpt.com/",
                       "Rebuild from safe mode must navigate back to home instead of blindly retrying risky route")
        XCTAssertEqual(model.recoveryAttempts, 1)
    }

    func testStaleOrDuplicateCallbacksAreIdempotent() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        let model = OptimizedAppModel()
        model.supervisor = supervisor

        let gen0 = model.webViewGeneration
        model.markProcessTerminated(route: "home", isSynthetic: false)
        XCTAssertEqual(supervisor.verifiedTerminationCount, 1, "First termination must count as 1")
        XCTAssertTrue(supervisor.isSafeModeActive)
        XCTAssertFalse(supervisor.isCircuitOpen)

        // Duplicate callback on the same dead WebView / generation
        model.markProcessTerminated(route: "home", isSynthetic: false)

        XCTAssertTrue(model.processTerminated)
        XCTAssertEqual(supervisor.verifiedTerminationCount, 1, "Duplicate callback on same generation must not increment verified termination count")
        XCTAssertFalse(supervisor.isCircuitOpen, "Circuit breaker must not open on duplicate callback from single termination")
        XCTAssertEqual(model.webViewGeneration, gen0, "Duplicate callbacks must not trigger rebuild")
    }

    func testManualRebuildThenRealSecondExitOpensCircuit() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        let model = OptimizedAppModel()
        model.supervisor = supervisor

        let gen0 = model.webViewGeneration
        // 1st verified termination
        model.markProcessTerminated(route: "conversation", isSynthetic: false)
        XCTAssertEqual(supervisor.verifiedTerminationCount, 1)
        XCTAssertFalse(supervisor.isCircuitOpen)
        XCTAssertTrue(model.processTerminated)
        XCTAssertTrue(supervisor.isSafeModeActive)

        // Duplicate callback on same generation must remain count=1
        model.markProcessTerminated(route: "conversation", isSynthetic: false)
        XCTAssertEqual(supervisor.verifiedTerminationCount, 1)

        // User explicitly confirms rebuild
        model.rebuildAfterConfirmation()
        XCTAssertFalse(model.processTerminated)
        XCTAssertFalse(supervisor.isSafeModeActive)
        XCTAssertFalse(supervisor.isCircuitOpen)
        let gen1 = model.webViewGeneration
        XCTAssertNotEqual(gen1, gen0, "Rebuild must create a new webView generation")

        // 2nd legitimate termination on new generation within 10 minutes
        model.markProcessTerminated(route: "conversation", isSynthetic: false)
        XCTAssertEqual(supervisor.verifiedTerminationCount, 2, "Second termination on new generation must count towards circuit")
        XCTAssertTrue(supervisor.isCircuitOpen, "Circuit breaker must open after 2 verified terminations")
        XCTAssertTrue(supervisor.isSafeModeActive)
        XCTAssertTrue(model.processTerminated)
    }

    func testSyntheticTerminationDoesNotEmitRemoteContentTerminatedTelemetry() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        let model = OptimizedAppModel()
        model.supervisor = supervisor
        let telemetry = OptimizedTelemetry(defaults: testDefaults)

        let initialEvent = telemetry.lastEvent
        XCTAssertFalse(initialEvent.contains("web_terminated"))

        // Simulate user triggering simulated termination action
        model.simulateProcessTermination()

        // Verify Supervisor recorded simulated_termination, NOT verified
        XCTAssertTrue(supervisor.isSafeModeActive)
        XCTAssertEqual(supervisor.verifiedTerminationCount, 0, "Simulated termination must not count as verified")
        let lastEntry = supervisor.journal.last
        XCTAssertEqual(lastEntry?.kind, "simulated_termination")
        XCTAssertFalse(lastEntry?.isVerified ?? true)

        // Verify telemetry did NOT record contentTerminated (web_terminated)
        XCTAssertFalse(telemetry.lastEvent.contains("web_terminated"),
                       "Synthetic termination must NOT record contentTerminated in telemetry")
    }

    func testExportReportIsContentFree() {
        let supervisor = NativeOptimizationSupervisor(defaults: testDefaults)
        supervisor.recordLaunch()
        supervisor.recordWebContentTermination(route: "conversation", isSynthetic: false)

        let report = supervisor.exportReport(telemetryReport: "本地遥测正常")
        XCTAssertTrue(report.contains("原生安全诊断"))
        XCTAssertTrue(report.contains("安全模式: 已激活"))
        XCTAssertTrue(report.contains("安全声明"))
        XCTAssertFalse(report.contains("token"))
        XCTAssertFalse(report.contains("cookie"))
        XCTAssertFalse(report.contains("password"))
        XCTAssertFalse(report.contains("Bearer"))
    }
}
