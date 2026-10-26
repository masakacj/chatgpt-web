import XCTest

final class ChatGPTWebOptimizedUITests: XCTestCase {
    func testProxyDefaultsFailClosedWithoutConfiguredEndpoints() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["proxy.configure.button"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews["optimized.webview"].exists,
                       "Missing proxy must not silently load ChatGPT directly")
        XCTAssertTrue(app.buttons["navigation.proxy.button"].exists)
    }

    func testOptimizedAppLaunchesItsIndependentWebView() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-proxy-direct"]
        app.launch()
        XCTAssertTrue(app.webViews["optimized.webview"].waitForExistence(timeout: 15))
    }
}
