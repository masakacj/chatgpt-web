import XCTest

final class PCSidebarUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func paired(_ flag: String = "") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--pc-companion-network-fixture"] + (flag.isEmpty ? [] : [flag])
        app.launch()
        XCTAssertTrue(app.textViews["pc.remote.composer"].waitForExistence(timeout: 15))
        app.buttons["连接"].tap(); app.buttons["读取 PC 会话"].tap()
        let tab = app.buttons["联调测试会话"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        XCTAssertTrue(app.staticTexts["联调初始答案"].waitForExistence(timeout: 10))
        return app
    }
    func testDefiniteNotSentPreservesDraftAndDoesNotWaitForever() throws {
        let app = paired("--pc-fixture-not-sent")
        let editor = app.textViews["pc.remote.composer"]
        editor.tap(); editor.typeText("keep unsent draft")
        app.buttons["发送"].tap()
        let error = app.staticTexts["pc.remote.error"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "本次未发送"), object: error)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 12), .completed)
        XCTAssertEqual(editor.value as? String, "keep unsent draft")
        XCTAssertFalse(app.buttons["核对发送回执"].exists)
        XCTAssertTrue(app.staticTexts["pc.fixture.counters"].label.contains("发送请求：1"))
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testProjectsExpandSearchAndSwitchNativeConversation() throws {
        let app = paired()
        app.buttons["pc.remote.sidebar"].tap()
        let project = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Project Alpha")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let expand = app.buttons["pc.sidebar.expand.g-p-aaaaaaaaaaaaaaaa"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); expand.tap()
        let chat = app.buttons["pc.sidebar.chat.22222222-2222-4222-8222-222222222222"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Project")
        XCTAssertFalse(app.buttons["pc.sidebar.chat.11111111-1111-4111-8111-111111111111"].exists)
        chat.tap()
        XCTAssertTrue(app.staticTexts["目录切换成功"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertTrue(app.staticTexts["pc.fixture.counters"].label.contains("发送请求：0"))
    }
}
