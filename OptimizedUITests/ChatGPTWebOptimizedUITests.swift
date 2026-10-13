import XCTest

final class ChatGPTWebOptimizedUITests: XCTestCase {
    func testOptimizedAppLaunchesItsIndependentWebView() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.webViews["optimized.webview"].waitForExistence(timeout: 15))
    }
}
