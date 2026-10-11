import XCTest

final class PCCompanionUITests: XCTestCase {
    func testOfflineNativeReaderDoesNotLoadWebView() throws {
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--pc-companion-fixture"]
        app.launch()
        let editor=app.textViews["pc.remote.composer"]
        XCTAssertTrue(editor.waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["已从 PC 同步的最新答案。手机原生界面无需加载完整网页。"].exists)
        XCTAssertEqual(app.webViews.count,0,"Remote mode must not retain a hidden heavy WKWebView")
        editor.tap();editor.typeText("local draft")
        XCTAssertFalse(app.buttons["发送"].isEnabled,"Offline snapshot is not a live writable PC connection")
        XCTAssertFalse(app.buttons["同步草稿"].isEnabled)
        app.buttons["连接"].tap()
        XCTAssertTrue(app.secureTextFields["配对密钥"].waitForExistence(timeout:5))
        XCTAssertTrue(app.textFields["HTTPS 服务地址"].exists)
    }
}
