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
    func testSafariWKABBenchmark()
        throws
    {
        let app =
            XCUIApplication()

        app.launchArguments = [
            "--ab-benchmark-sequence",
            "--ab-benchmark-base-url",
            "http://127.0.0.1:8765/fixture"
        ]

        app.launch()

        XCTAssertTrue(
            app.wait(
                for: .runningForeground,
                timeout: 10
            ),
            "A-B sequence app did not remain foreground"
        )

        let status =
            app.staticTexts[
                "ab.sequence.status"
            ]

        XCTAssertTrue(
            status.waitForExistence(
                timeout: 10
            ),
            "A-B sequence status did not appear"
        )

        let deadline =
            Date()
                .addingTimeInterval(
                    125
                )

        while
            Date() < deadline &&
            !status.label
                .hasPrefix(
                    "DONE"
                )
        {
            RunLoop.current.run(
                until:
                    Date()
                        .addingTimeInterval(
                            0.35
                        )
            )
        }

        XCTAssertTrue(
            status.label
                .hasPrefix(
                    "DONE"
                ),
            "A-B sequence did not finish: \(status.label)"
        )
    }

}
