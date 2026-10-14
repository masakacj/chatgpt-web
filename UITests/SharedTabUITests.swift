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
        // The accessibility frame can extend below keyboard/composer insets.
        // Tap actual visible blank transcript, not a point covered by the keyboard.
        let transcript = app.scrollViews["shared.transcript"].frame
        let keyboard = app.keyboards.firstMatch.frame
        let editor = composer(app).frame
        let answer = app.staticTexts["原生测试答案 A"].frame
        let copy = app.buttons["复制消息"].firstMatch.frame
        let top = max(transcript.minY + 12, max(answer.maxY, copy.maxY) + 16)
        let bottom = min(transcript.maxY, min(keyboard.minY, editor.minY)) - 16
        XCTAssertGreaterThan(bottom, top, "There must be visible blank transcript above the composer")
        let point = CGPoint(x: transcript.midX, y: (top + bottom) / 2)
        XCTAssertFalse(keyboard.contains(point))
        XCTAssertFalse(editor.contains(point))
        print("Keyboard acceptance geometry: transcript=\(transcript), keyboard=\(keyboard), editor=\(editor), tap=\(point)")
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "shared-before-blank-tap"; before.lifetime = .keepAlways; add(before)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY)).tap()
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
    func testStructuredRemoteRichContentIsNativeAndPreservesFallbacks() throws {
        let app = launch("--shared-fixture-rich")
        let transcript = app.scrollViews["shared.transcript"]
        transcript.swipeUp()
        XCTAssertTrue(app.staticTexts["富内容验收"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Name"].exists)
        XCTAssertTrue(app.staticTexts["Alpha"].exists)
        XCTAssertTrue(app.staticTexts["print(42)"].exists)
        XCTAssertTrue(app.staticTexts["这是引用"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'notes.pdf'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["PC 私有图片 · 请在 PC 查看"].exists)
        let remoteLink = app.buttons["shared.pcLink"].firstMatch
        XCTAssertTrue(remoteLink.exists); remoteLink.tap()
        wait("label CONTAINS '交互：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testBridgeStageCanBeSelectedWithoutReusingOldPairing() throws {
        let app = launch()
        app.buttons["更多"].tap()
        let settings = app.buttons["连接设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let change = app.buttons["shared.useTestBridge"]
        XCTAssertTrue(change.waitForExistence(timeout: 8))
        change.tap()
        let endpoint = app.textFields["HTTPS 服务地址"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 8))
        wait("value == 'https://chatgpt-bridge-test.78175132.xyz'", on: endpoint)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS '127.0.0.1:13213/local/pair'")).firstMatch.exists)
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testRunningPCWithDisabledNativeSendPreservesLocalDraft() throws {
        let app = launch("--shared-fixture-busy-blocked")
        let input = composer(app)
        input.tap(); input.typeText("do not send while PC is responding")
        XCTAssertFalse(app.buttons["shared.send"].isEnabled)
        XCTAssertTrue(String(describing: composer(app).value).contains("do not send while PC is responding"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '生成中'")).firstMatch.exists)
    }
    func testRunningPCWithEnabledNativeSendAcceptsFollowUpOnce() throws {
        let app = launch("--shared-fixture-busy-send")
        let input = composer(app)
        input.tap(); input.typeText("follow-up while responding")
        XCTAssertTrue(app.buttons["shared.send"].isEnabled)
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.staticTexts["原生回复：follow-up while responding"].waitForExistence(timeout: 10))
        wait("label CONTAINS '发送请求：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("草稿同步：0"))
    }
    func testWaitingPCApprovalDisablesSendAndKeepsDraft() throws {
        let app = launch("--shared-fixture-interaction")
        let input = composer(app)
        input.tap(); input.typeText("draft while approval is pending")
        XCTAssertFalse(app.buttons["shared.send"].isEnabled)
        XCTAssertTrue(String(describing: composer(app).value).contains("draft while approval is pending"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
        XCTAssertTrue(app.buttons["允许一次"].exists)
    }
    func testVisibleHeaderIndicatorDuringPCGeneration() throws {
        let app = launch("--shared-fixture-busy-send")
        XCTAssertTrue(app.descendants(matching: .any)["shared.header.running"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["生成中"].exists)
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testNativeUploadHandsToPCWithoutSubmittingPrompt() throws {
        let app = launch()
        let upload = app.buttons["shared.fixture.upload"]
        XCTAssertTrue(upload.waitForExistence(timeout: 8))
        upload.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS '已交给 PC 网页附件控件'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testNativeModelAndThinkingControlsComeFromBoundPC() throws {
        let app = launch()
        XCTAssertTrue(app.images["shared.header.completed"].exists ||
                      app.otherElements["shared.header.completed"].exists ||
                      app.staticTexts["shared.title"].exists)
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        let high = app.buttons["shared.model.fixture-model-option-0001"]
        XCTAssertTrue(high.waitForExistence(timeout: 8))
        high.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '已在 PC 网页选择'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testActiveProjectConversationAppearsAboveNativeRecentList() throws {
        let app = launch("--shared-fixture-sidebar")
        app.buttons["shared.sidebar"].tap()
        XCTAssertTrue(app.staticTexts["最近活跃（含项目对话）"].waitForExistence(timeout: 8))
        let chat = app.buttons["shared.chat.22222222-2222-4222-8222-222222222222"].firstMatch
        XCTAssertTrue(chat.exists)
        XCTAssertEqual(chat.value as? String, "生成中")
        XCTAssertTrue(app.buttons["shared.attach"].exists)
    }
    func testEdgeSwipeOpensAndLeftSwipeClosesNativeSidebar() throws {
        let app = launch()
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.48))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.48))
        from.press(forDuration: 0.06, thenDragTo: to)
        let search = app.textFields["shared.search.input"]
        XCTAssertTrue(search.waitForExistence(timeout: 6))
        let closeFrom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        let closeTo = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        closeFrom.press(forDuration: 0.06, thenDragTo: closeTo)
        wait("exists == false", on: search, timeout: 6)
    }
    func testNativeSidebarIndicatorValuesAreNotInvented() throws {
        let app = launch("--shared-fixture-sidebar")
        app.buttons["shared.sidebar"].tap()
        let active = app.buttons["shared.chat.22222222-2222-4222-8222-222222222222"]
        let unread = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"]
        XCTAssertTrue(active.waitForExistence(timeout: 6))
        XCTAssertTrue(unread.waitForExistence(timeout: 6))
        XCTAssertEqual(active.value as? String, "生成中")
        XCTAssertEqual(unread.value as? String, "未读")
    }
    func testNativePublicLinksAndDownloadControlsAreAvailable() throws {
        let app = launch("--shared-fixture-native-resources")
        let content = app.scrollViews["shared.transcript"]
        content.swipeUp()
        XCTAssertTrue(app.buttons["shared.nativeLink"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["shared.file.preview"].exists)
        XCTAssertTrue(app.buttons["shared.file.download"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '仅 PC 可获取'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testBackgroundForegroundTimeoutRecoversWithoutRedError() throws {
        let app = launch("--shared-fixture-resume-timeout")
        XCUIDevice.shared.press(.home)
        app.activate()
        wait("label == '与 PC 共用此标签页'", on: app.staticTexts["shared.status"], timeout: 20)
        XCTAssertFalse(app.staticTexts["The request timed out."].exists)
        XCTAssertFalse(app.staticTexts["请求超时"].exists)
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].exists)
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
    func testAuthenticatedSameServerIdSelectsHomeWithoutChangingPCExecutor() throws {
        let app = launch("--shared-fixture-dual")
        wait("label CONTAINS 'Home HTTPS'", on: app.staticTexts["shared.route"])
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].exists)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testHome502SwitchesOnlyGETToVerifiedCloudflare() throws {
        let app = launch("--shared-fixture-home-502")
        wait("label CONTAINS 'Cloudflare 443'", on: app.staticTexts["shared.route"], timeout: 12)
        let counts = app.staticTexts["shared.fixture.counters"].label
        XCTAssertTrue(counts.contains("Home读取：1"), counts)
        XCTAssertTrue(counts.contains("CF读取："), counts)
        XCTAssertTrue(counts.contains("发送请求：0"), counts)
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].exists)
    }
    func testHomeNetworkLossFallsBackWithSameLoadedSnapshot() throws {
        let app = launch("--shared-fixture-home-network-lost")
        wait("label CONTAINS 'Cloudflare 443'", on: app.staticTexts["shared.route"], timeout: 12)
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].exists)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testHome401RefusesPrimaryAndKeepsCloudflare() throws {
        let app = launch("--shared-fixture-home-401")
        XCTAssertTrue(app.staticTexts["shared.route"].label.contains("Cloudflare"))
        XCTAssertTrue(app.staticTexts["shared.routeNotice"].label.contains("Home 配对认证失败"))
        composer(app).tap(); composer(app).typeText("cf after refused home")
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.staticTexts["原生回复：cf after refused home"].waitForExistence(timeout: 10))
        let counts = app.staticTexts["shared.fixture.counters"].label
        XCTAssertTrue(counts.contains("Home发送：0"), counts)
        XCTAssertTrue(counts.contains("CF发送：1"), counts)
    }
    func testMismatchedOrUnprovenHomeIdentityNeverHandlesWrites() throws {
        for flag in ["--shared-fixture-home-mismatch", "--shared-fixture-home-noid", "--shared-fixture-cf-noid"] {
            let app = launch(flag)
            XCTAssertTrue(app.staticTexts["shared.route"].label.contains("Cloudflare"))
            XCTAssertTrue(app.staticTexts["shared.routeNotice"].exists)
            XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
            app.terminate()
        }
    }
    func testUnknownHomePOSTNeverReplaysAcrossLinesOrErasesDraft() throws {
        let app = launch("--shared-fixture-home-unknown-post")
        let input = composer(app)
        input.tap(); input.typeText("unknown-home-send")
        XCTAssertTrue(app.buttons["shared.send"].isEnabled)
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.buttons["shared.receipt"].waitForExistence(timeout: 10))
        app.buttons["shared.receipt"].tap()
        wait("label CONTAINS '发送请求：1'", on: app.staticTexts["shared.fixture.counters"])
        let counts = app.staticTexts["shared.fixture.counters"].label
        XCTAssertTrue(counts.contains("Home发送：1"), counts)
        XCTAssertTrue(counts.contains("CF发送：0"), counts)
        XCTAssertTrue(String(describing: composer(app).value).contains("unknown-home-send"))
        XCTAssertFalse(app.buttons["shared.send"].isEnabled)
    }
    func testLegacy58443OriginPreservesDraftAfterTransportRepointsTo443() throws {
        let app = launch("--shared-fixture-legacy-origin")
        XCTAssertTrue(String(describing: composer(app).value).contains("原58443未发送草稿"))
        XCTAssertTrue(app.staticTexts["shared.route"].label.contains("Cloudflare"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
        app.buttons["更多"].tap()
        app.buttons["连接设置"].tap()
        let origin = app.textFields["HTTPS 服务地址"]
        XCTAssertTrue(origin.waitForExistence(timeout: 5))
        XCTAssertEqual(origin.value as? String, "https://chatgpt-pc.781751.xyz:58443")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '原配对和本地草稿'")).firstMatch.exists)
    }
    func testAllReadLinesOfflinePreservesSnapshotAndDisablesSend() throws {
        let app = launch("--shared-fixture-both-offline")
        wait("label CONTAINS '离线'", on: app.staticTexts["shared.route"], timeout: 20)
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].exists)
        XCTAssertFalse(app.buttons["shared.send"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["shared.header.completed"].exists)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testLongPoll20SecondsDoesNotProducePrematureOfflineUI() throws {
        let app = launch("--shared-fixture-20s-poll")
        XCTAssertTrue(app.staticTexts["shared.route"].label.contains("Cloudflare"))
        Thread.sleep(forTimeInterval: 21.5)
        XCTAssertTrue(app.staticTexts["shared.route"].label.contains("Cloudflare"))
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].exists)
        XCTAssertFalse(app.staticTexts["shared.route"].label.contains("离线"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }

    func testUnknownHomeUploadUsesOriginalUploadIdForReadOnlyReceiptLookup() throws {
        let app = launch("--shared-fixture-home-upload-unknown")
        app.buttons["shared.fixture.upload"].tap()
        XCTAssertTrue(app.buttons["shared.receipt"].waitForExistence(timeout: 10))
        app.buttons["shared.receipt"].tap()
        let counts = app.staticTexts["shared.fixture.counters"].label
        XCTAssertTrue(counts.contains("Home上传：1"), counts)
        XCTAssertTrue(counts.contains("CF上传：0"), counts)
        XCTAssertTrue(counts.contains("发送请求：0"), counts)
        XCTAssertTrue(app.staticTexts["shared.controlNotice"].label.contains("不会"))
        app.buttons["shared.action.review"].tap()
        app.buttons["已核对 PC，仅解除本地锁定"].tap()
        wait("exists == false", on: app.buttons["shared.receipt"])
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("Home上传：1"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("CF上传：0"))
    }
    func testUnknownHomeModelChoiceChecksReceiptRatherThanClickingAgain() throws {
        let app = launch("--shared-fixture-home-model-unknown")
        app.buttons["shared.modelPicker"].tap()
        let option = app.buttons["shared.model.fixture-model-option-0001"]
        XCTAssertTrue(option.waitForExistence(timeout: 8))
        option.tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["shared.receipt"].waitForExistence(timeout: 10))
        app.buttons["shared.receipt"].tap()
        let counts = app.staticTexts["shared.fixture.counters"].label
        XCTAssertTrue(counts.contains("Home模型：1"), counts)
        XCTAssertTrue(counts.contains("CF模型：0"), counts)
        XCTAssertTrue(counts.contains("发送请求：0"), counts)
    }

}
