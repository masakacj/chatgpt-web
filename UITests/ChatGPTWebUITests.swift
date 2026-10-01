import XCTest

final class ChatGPTWebUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInAppSafariContainerLaunches()
        throws
    {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(
                for: .runningForeground,
                timeout: 10
            ),
            "In-app Safari container did not remain in foreground"
        )
    }
}
