import XCTest

final class SharedTabUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ extra: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--shared-tab-fixture"] + (extra.map { [$0] } ?? [])
        app.launch()
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.webViews.count, 0)
        return app
    }
    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let view = app.textViews["shared.composer"]
        if view.exists { return view }
        return app.textFields["shared.composer"]
    }
    private func wait(_ condition: String, on object: Any, timeout: TimeInterval = 8) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: condition), object: object)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
    private func searchB(_ app: XCUIApplication) {
        app.buttons["shared.sidebar"].tap()
        let input = app.textFields["shared.search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("older")
        app.buttons["shared.search"].tap()
        let target = app.buttons["shared.chat.22222222-2222-4222-8222-222222222222"]
        XCTAssertTrue(target.waitForExistence(timeout: 8)); target.tap()
        XCTAssertTrue(app.staticTexts["原生历史答案 B"].waitForExistence(timeout: 8))
    }
    func testNativeBlankTapDismissesKeyboardAndSendWorksOnce() throws {
        let app = launch(); let input = composer(app)
        input.tap(); input.typeText("mobile send once")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.scrollViews["shared.transcript"].coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.72)).tap()
        wait("exists == false", on: app.keyboards.firstMatch)
        XCTAssertTrue(app.buttons["shared.send"].isEnabled)
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.staticTexts["原生回复：mobile send once"].waitForExistence(timeout: 10))
        wait("label CONTAINS '发送请求：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("草稿同步：0"))
        XCTAssertFalse(String(describing: composer(app).value).contains("mobile send once"))
        XCTAssertFalse(String(describing: composer(app).value).contains("PC_TEXT"))
    }
    func testPerChatDraftsSurviveSearchAndSwitchWithoutSyncingPC() throws {
        let app = launch(); composer(app).tap(); composer(app).typeText("draft A local")
        searchB(app)
        XCTAssertFalse(String(describing: composer(app).value).contains("draft A local"))
        composer(app).tap(); composer(app).typeText("draft B local")
        app.buttons["shared.sidebar"].tap()
        let a = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"]
        XCTAssertTrue(a.waitForExistence(timeout: 8)); a.tap()
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].waitForExistence(timeout: 8))
        XCTAssertTrue(String(describing: composer(app).value).contains("draft A local"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("草稿同步：0"))
        XCTAssertFalse(String(describing: composer(app).value).contains("PC_TEXT"))
    }
    func testNewChatFirstMessageAcquiresRealConversation() throws {
        let app = launch(); app.buttons["shared.new"].tap()
        wait("label == '新聊天'", on: app.staticTexts["shared.title"])
        composer(app).tap(); composer(app).typeText("ordinary first message")
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.staticTexts["原生回复：ordinary first message"].waitForExistence(timeout: 10))
        wait("label == '已创建的新聊天'", on: app.staticTexts["shared.title"])
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：1"))
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testNewChatInsideSelectedProject() throws {
        let app = launch(); app.buttons["shared.sidebar"].tap()
        let project = app.buttons["Project Alpha"]
        XCTAssertTrue(project.waitForExistence(timeout: 8)); project.tap()
        let create = app.buttons["shared.project.new.g-p-aaaaaaaaaaaaaaaa"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        wait("label == '新聊天'", on: app.staticTexts["shared.title"])
        XCTAssertTrue(app.staticTexts["Project Alpha"].exists)
        composer(app).tap(); composer(app).typeText("project first message")
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.staticTexts["原生回复：project first message"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Project Alpha"].exists)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：1"))
    }
    func testUnknownSendChecksReceiptWithoutReplayingAndAllowsOtherChat() throws {
        let app = launch("--shared-fixture-unknown")
        composer(app).tap(); composer(app).typeText("uncertain message")
        app.buttons["shared.send"].tap()
        let receipt = app.buttons["shared.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10)); receipt.tap()
        wait("label CONTAINS '发送请求：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(String(describing: composer(app).value).contains("uncertain message"))
        XCTAssertFalse(app.buttons["shared.send"].isEnabled)
        searchB(app)
        composer(app).tap(); composer(app).typeText("other chat draft")
        XCTAssertTrue(app.buttons["shared.send"].isEnabled)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：1"))
    }
    func testPCNavigationFollowsBoundTabWithoutNewBinding() throws {
        let app = launch("--shared-fixture-pc-switch")
        XCTAssertTrue(app.staticTexts["原生历史答案 B"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("导航：0"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testOlderMessagesRemainNativeAndReadable() throws {
        let app = launch("--shared-fixture-history")
        let more = app.buttons["shared.history"]
        XCTAssertTrue(more.waitForExistence(timeout: 8)); more.tap()
        app.scrollViews["shared.transcript"].swipeDown()
        XCTAssertTrue(app.staticTexts["更早的正式回复"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testExplicitInteractionRequiresConfirmationAndExecutesOnce() throws {
        let app = launch("--shared-fixture-interaction")
        let action = app.buttons["允许一次"]
        XCTAssertTrue(action.waitForExistence(timeout: 8)); action.tap()
        let confirm = app.buttons["shared.interaction.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        wait("label CONTAINS '交互：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
}
