import XCTest

final class ChatGPTWebOptimizedUITests: XCTestCase {
    func testBackButtonIsAvailableAndDisabledWithoutHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-fresh-launch"]
        app.launch()
        let back = app.buttons["navigation.back.button"]
        let forward = app.buttons["navigation.forward.button"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(forward.exists)
        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(forward.isEnabled)
    }

    func testProxyDefaultsFailClosedWithoutConfiguredEndpoints() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-fresh-launch"]
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

    func testNestedSidebarScrollAcceptsVerticalSwipeWithoutNetwork() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-proxy-direct", "-uitest-sidebar-scroll"]
        app.launch()
        let webView = app.webViews["optimized.webview"]
        XCTAssertTrue(webView.waitForExistence(timeout: 15))
        let bottom = webView.staticTexts["SIDEBAR_END"]
        XCTAssertTrue(bottom.waitForExistence(timeout: 15))
        XCTAssertFalse(bottom.isHittable, "bottom row must start outside the viewport")
        for _ in 0..<8 where !bottom.isHittable {
            webView.swipeUp()
        }
        XCTAssertTrue(bottom.isHittable, "nested HTML sidebar must respond to vertical touch scrolling")
    }
}
