import XCTest

final class ChatGPTWebUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWKWebViewShellLaunches()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing"
        ]
        app.launch()

        XCTAssertTrue(
            app.wait(
                for: .runningForeground,
                timeout: 10
            ),
            "WKWebView developer shell did not remain in foreground"
        )
    }

    func testNativeFloatingFallbackWhenWebKitStopsAnswering() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-panel-stall"
        ]
        app.launch()

        let anchor = app.buttons["chatgpt.web.floatingAnchor"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 15),
                      "Native floating button must exist independently of WebKit JS")
        anchor.tap()

        let fallback = app.alerts["网页响应缓慢"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 8),
                      "Stalled WebKit must produce a native fallback without page reload")
        XCTAssertTrue(fallback.buttons["返回 ChatGPT 首页"].exists)
        XCTAssertTrue(fallback.buttons["手动刷新当前页面…"].exists)

        fallback.buttons["手动刷新当前页面…"].tap()
        let confirm = app.alerts["确认刷新"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "Reload requires a second explicit confirmation to protect drafts")
        XCTAssertTrue(confirm.buttons["确认刷新"].exists)
        confirm.buttons["取消"].tap()

        // The same native floating anchor remains independently touchable.
        XCTAssertTrue(anchor.exists)
    }

    func testWKWebViewResultOnlyStress()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--webkit-stress"
        ]
        app.launch()

        XCTAssertTrue(
            app.wait(
                for: .runningForeground,
                timeout: 10
            ),
            "WKWebView stress app did not remain in foreground"
        )

        let result =
            app.staticTexts[
                "webkit.stress.result"
            ]

        XCTAssertTrue(
            result.waitForExistence(
                timeout: 12
            ),
            "WKWebView stress status did not appear"
        )

        let deadline =
            Date().addingTimeInterval(
                18
            )

        while
            Date() < deadline &&
            result.label == "RUNNING"
        {
            RunLoop.current.run(
                until:
                    Date().addingTimeInterval(
                        0.25
                    )
            )
        }

        let status =
            result.label

        XCTAssertTrue(
            status.hasPrefix("PASS"),
            "WKWebView Result Only stress failed: \(status)"
        )
    }
}
