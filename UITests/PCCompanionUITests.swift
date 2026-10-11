import XCTest

final class PCCompanionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func waitLabel(_ element: XCUIElement, contains text: String, timeout: Double = 12) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: timeout), .completed)
    }
    private func paired(_ mode: String = "") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--pc-companion-network-fixture"] + (mode.isEmpty ? [] : [mode])
        app.launch()
        XCTAssertTrue(app.textViews["pc.remote.composer"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.webViews.count, 0)
        app.buttons["连接"].tap()
        app.buttons["读取 PC 会话"].tap()
        let tab = app.buttons["联调测试会话"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        XCTAssertTrue(app.staticTexts["pc.fixture.counters"].waitForExistence(timeout: 10))
        return app
    }
    func testOfflineNativeReaderDoesNotLoadWebView() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--pc-companion-fixture"]; app.launch()
        let editor = app.textViews["pc.remote.composer"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["已从 PC 同步的最新答案。手机原生界面无需加载完整网页。"].exists)
        XCTAssertEqual(app.webViews.count, 0, "No hidden WebKit instance in PC mode")
        editor.tap(); editor.typeText("local draft")
        XCTAssertFalse(app.buttons["发送"].isEnabled); XCTAssertFalse(app.buttons["同步草稿"].isEnabled)
        app.buttons["连接"].tap()
        XCTAssertTrue(app.secureTextFields["配对密钥"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["HTTPS 服务地址"].value as? String, "https://chatgpt-pc.781751.xyz:58443")
    }
    func testTransientReadFailureReconnectsWithoutSending() throws {
        let app = paired("--pc-fixture-reconnect")
        XCTAssertTrue(app.staticTexts["重连后答案"].waitForExistence(timeout: 15))
        waitLabel(app.staticTexts["pc.fixture.counters"], contains: "发送请求：0")
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testExpiredSubscriptionReopensSameConversation() throws {
        let app = paired("--pc-fixture-expire")
        XCTAssertTrue(app.staticTexts["会话重建成功"].waitForExistence(timeout: 15))
        waitLabel(app.staticTexts["pc.fixture.counters"], contains: "订阅：2")
        waitLabel(app.staticTexts["pc.fixture.counters"], contains: "发送请求：0")
    }
    func testDraftConflictPreservesPhoneText() throws {
        let app = paired("--pc-fixture-conflict")
        let editor = app.textViews["pc.remote.composer"]
        editor.tap(); editor.typeText("phone draft must survive")
        app.buttons["同步草稿"].tap()
        waitLabel(app.staticTexts["pc.remote.error"], contains: "已阻止覆盖")
        XCTAssertEqual(editor.value as? String, "phone draft must survive")
        waitLabel(app.staticTexts["pc.fixture.counters"], contains: "发送请求：0")
    }
    func testUnknownSendQueriesReceiptAndRetainsNextDraft() throws {
        let app = paired("--pc-fixture-unknown")
        let editor = app.textViews["pc.remote.composer"]
        editor.tap(); editor.typeText("receipt test")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["核对发送回执"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["发送"].isEnabled)
        editor.tap(); editor.typeText(" next draft")
        app.buttons["核对发送回执"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["核对发送回执"])
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 12), .completed)
        XCTAssertTrue((editor.value as? String ?? "").contains("next draft"), "Receipt must not erase text typed after Send")
        waitLabel(app.staticTexts["pc.fixture.counters"], contains: "发送请求：1")
    }
    func testPublicHTTPSUsesSystemTrustAndRejectsMissingPairing() throws {
        // Real external gateway, no bearer and no account content. Unlike the
        // isolated protocol tests above, this verifies actual Apple TLS trust.
        let done = expectation(description: "public HTTPS401")
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: c)
        session.dataTask(with: URL(string: "https://chatgpt-pc.781751.xyz:58443/v1/health")!) { data, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
            XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.contains("pairing_required") == true)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20); session.invalidateAndCancel()
    }
}
