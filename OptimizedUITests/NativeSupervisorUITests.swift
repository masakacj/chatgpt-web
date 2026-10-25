import XCTest

final class NativeSupervisorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func findSimulatedTerminationButton() -> XCUIElement {
        let button = app.buttons["diagnostics.simulate.termination"]
        // The medium-height diagnostics sheet uses a lazily mounted List.
        let list = app.collectionViews.firstMatch
        for _ in 0..<3 where !button.exists {
            if list.exists { list.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Simulation button must be reachable in diagnostics")
        return button
    }

    func testSimulatedTerminationShowsNativeSafeModeAndAllowsRebuild() {
        app.launch()

        // 1. Verify app launches with its independent webview
        let webView = app.webViews["optimized.webview"]
        XCTAssertTrue(webView.waitForExistence(timeout: 15), "Optimized WebView should exist at launch")

        // 2. Open Diagnostics sheet
        let diagnosticsButton = app.buttons["navigation.diagnostics.button"]
        XCTAssertTrue(diagnosticsButton.waitForExistence(timeout: 5), "Diagnostics button should be accessible")
        diagnosticsButton.tap()

        // 3. Find and trigger the simulated termination test action
        let simulateButton = findSimulatedTerminationButton()
        simulateButton.tap()

        // 4. Verify Native Safe Mode view replaces the web view (no WebContent instance beneath)
        let safeModeView = app.scrollViews["native.safemode.view"]
        XCTAssertTrue(safeModeView.waitForExistence(timeout: 5), "Native Safe Mode screen must be presented")
        XCTAssertFalse(webView.exists, "Optimized WebView must not exist when safe mode is active")

        // 5. Verify Safe Mode interactive controls
        let rebuildButton = app.buttons["safemode.rebuild.button"]
        XCTAssertTrue(rebuildButton.exists, "User-confirmed rebuild button must be visible in safe mode")

        let staySafeButton = app.buttons["safemode.staysafe.button"]
        XCTAssertTrue(staySafeButton.exists, "Stay in safe mode button must be visible")

        let mirrorInstructions = app.descendants(matching: .any)["safemode.mirror.instructions"]
        for _ in 0..<3 where !mirrorInstructions.exists { safeModeView.swipeUp() }
        XCTAssertTrue(mirrorInstructions.waitForExistence(timeout: 5),
                      "Mirror fallback instructions must be reachable in native safe mode")

        safeModeView.swipeDown()
        let exportButton = app.descendants(matching: .any)["safemode.export.button"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5),
                      "Diagnostics export button must be present in safe mode")

        // 6. Verify top-level diagnostics remains interactive while in safe mode
        XCTAssertTrue(diagnosticsButton.isHittable, "Diagnostics button must remain interactive even when safe mode is active")
        diagnosticsButton.tap()
        let doneButton = app.buttons["完成"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        // 7. Perform user-confirmed rebuild
        XCTAssertTrue(rebuildButton.waitForExistence(timeout: 5))
        rebuildButton.tap()

        // 8. Verify safe mode view dismisses and web view is restored
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "WebView must be restored after confirmed rebuild")
    }

    func testStayInSafeModeKeepsSafeScreenActive() {
        app.launch()

        let diagnosticsButton = app.buttons["navigation.diagnostics.button"]
        XCTAssertTrue(diagnosticsButton.waitForExistence(timeout: 10))
        diagnosticsButton.tap()

        let simulateButton = findSimulatedTerminationButton()
        simulateButton.tap()

        let safeModeView = app.scrollViews["native.safemode.view"]
        XCTAssertTrue(safeModeView.waitForExistence(timeout: 5))

        let staySafeButton = app.buttons["safemode.staysafe.button"]
        XCTAssertTrue(staySafeButton.exists)
        staySafeButton.tap()

        // Safe mode screen remains active
        XCTAssertTrue(safeModeView.exists, "Safe mode screen must stay active when user chooses to stay safe")
        let webView = app.webViews["optimized.webview"]
        XCTAssertFalse(webView.exists, "WebView must not exist when user stays in safe mode")
    }

    func testPersistedOpenCircuitLaunchesDirectlyIntoNativeSafeModeWithoutWebView() {
        let circuitApp = XCUIApplication()
        circuitApp.launchArguments = ["-uitest-circuit-open"]
        circuitApp.launch()

        let safeModeView = circuitApp.scrollViews["native.safemode.view"]
        XCTAssertTrue(safeModeView.waitForExistence(timeout: 5), "App must launch directly into safe mode when circuit is open")

        let webView = circuitApp.webViews["optimized.webview"]
        XCTAssertFalse(webView.exists, "WebView must NOT be instantiated when launching into safe mode")
    }
}
