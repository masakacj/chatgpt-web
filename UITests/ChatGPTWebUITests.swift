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
        guard
            let baseURL =
                ProcessInfo.processInfo
                    .environment[
                        "CGPT_AB_BASE_URL"
                    ],
            !baseURL.isEmpty
        else {
            throw XCTSkip(
                "CGPT_AB_BASE_URL is not set"
            )
        }

        let modes = [
            "safari",
            "wk"
        ]

        let scenarios = [
            "raw",
            "pruned"
        ]

        for scenario in scenarios {
            for mode in modes {
                for iteration in 0..<3 {
                    let runID =
                        "\(mode)-\(scenario)-\(iteration)-\(Int(Date().timeIntervalSince1970 * 1000))"

                    guard
                        var components =
                            URLComponents(
                                string:
                                    baseURL
                            )
                    else {
                        XCTFail(
                            "Invalid benchmark URL"
                        )
                        return
                    }

                    components.queryItems = [
                        URLQueryItem(
                            name: "mode",
                            value: mode
                        ),
                        URLQueryItem(
                            name: "scenario",
                            value: scenario
                        ),
                        URLQueryItem(
                            name: "run",
                            value: runID
                        )
                    ]

                    guard
                        let url =
                            components.url?
                                .absoluteString
                    else {
                        XCTFail(
                            "Failed to build benchmark URL"
                        )
                        return
                    }

                    XCTContext.runActivity(
                        named:
                            "\(mode) / \(scenario) / \(iteration + 1)"
                    ) { _ in
                        let app =
                            XCUIApplication()

                        app.launchArguments = [
                            "--ab-benchmark-mode",
                            mode,
                            "--ab-benchmark-url",
                            url
                        ]

                        app.launch()

                        XCTAssertTrue(
                            app.wait(
                                for:
                                    .runningForeground,
                                timeout: 10
                            ),
                            "Benchmark app did not remain foreground"
                        )

                        RunLoop.current.run(
                            until:
                                Date()
                                    .addingTimeInterval(
                                        5.5
                                    )
                        )

                        app.terminate()

                        RunLoop.current.run(
                            until:
                                Date()
                                    .addingTimeInterval(
                                        0.35
                                    )
                        )
                    }
                }
            }
        }
    }

}
