import XCTest

final class ChatGPTWebUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSafariLauncherIsReady()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments.append(
            "--ui-testing"
        )
        app.launch()

        XCTAssertTrue(
            app.buttons["打开 ChatGPT"]
                .waitForExistence(
                    timeout: 10
                ),
            "Safari launcher button did not appear"
        )
    }
}
