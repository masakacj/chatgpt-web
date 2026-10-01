import XCTest

final class ChatGPTWebUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSafariContainerLaunches()
        throws
    {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(
                for: .runningForeground,
                timeout: 10
            ),
            "Safari container app did not reach foreground"
        )
    }
}
