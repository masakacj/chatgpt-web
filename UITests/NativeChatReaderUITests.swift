import XCTest

final class NativeChatReaderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func paired(_ flag: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--pc-companion-network-fixture", flag]
        app.launch()
        XCTAssertTrue(app.textViews["pc.remote.composer"].waitForExistence(timeout: 15))
        app.buttons["连接"].tap(); app.buttons["读取 PC 会话"].tap()
        let chat = app.buttons["联调测试会话"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10)); chat.tap()
        XCTAssertTrue(app.staticTexts["pc.fixture.counters"].waitForExistence(timeout: 10))
        return app
    }
    func testNoAnswerShowsThinkingWithoutToolOrReasoningBody() throws {
        let app = paired("--pc-fixture-thinking")
        XCTAssertTrue(app.staticTexts["等待最新回复"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["pc.response.thinking"].exists || app.staticTexts["思考中"].exists)
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertTrue(app.buttons["pc.remote.sidebar"].exists)
        XCTAssertFalse(app.buttons["发送"].isEnabled)
    }
    func testEarlierMessagesStayReadableWithLatestReply() throws {
        let app = paired("--pc-fixture-reader")
        let history = app.buttons["pc.history.more"]
        XCTAssertTrue(history.waitForExistence(timeout: 10)); history.tap()
        let older = app.staticTexts["历史正式回复"]
        if !older.waitForExistence(timeout: 5) { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(older.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["pc.history.more"].exists)
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertTrue(app.staticTexts["pc.fixture.counters"].label.contains("发送请求：0"))
    }
    func testCurrentInteractionRequiresConfirmationAndExecutesOnce() throws {
        let app = paired("--pc-fixture-reader")
        let action = app.buttons["pc.action.interaction-test-11111"]
        XCTAssertTrue(action.waitForExistence(timeout: 10)); action.tap()
        XCTAssertTrue(app.buttons["pc.action.confirm"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["pc.fixture.counters"].label.contains("操作：0"))
        action.tap(); app.buttons["pc.action.confirm"].tap()
        XCTAssertTrue(app.staticTexts["操作后正式回复"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["pc.action.interaction-test-11111"].exists)
        XCTAssertTrue(app.staticTexts["pc.fixture.counters"].label.contains("操作：1"))
        XCTAssertTrue(app.staticTexts["pc.fixture.counters"].label.contains("发送请求：0"))
    }
}
