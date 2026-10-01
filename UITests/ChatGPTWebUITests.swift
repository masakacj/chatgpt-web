import XCTest

final class ChatGPTWebUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFloatingControlIsVisibleAndHittable()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments.append(
            "--ui-testing"
        )
        app.launch()

        let button =
            app.buttons[
                "chatgpt.web.floatingAnchor"
            ]

        XCTAssertTrue(
            button.waitForExistence(
                timeout: 10
            ),
            "Native anchor did not appear"
        )

        XCTAssertTrue(
            button.isHittable,
            "Native anchor is not hittable"
        )

        XCTAssertFalse(
            app.buttons[
                "ChatGPT Web 控制"
            ].exists,
            "Hybrid container should not expose the JS fallback S button"
        )
    }
}
