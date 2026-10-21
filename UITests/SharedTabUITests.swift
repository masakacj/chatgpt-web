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
    func testUnknownSendMakesReasonVisibleAndAllowsOnlyDifferentNewText() throws {
        let app = launch("--shared-fixture-unknown")
        let input = composer(app)
        input.tap(); input.typeText("an unconfirmed old message")
        let send = app.buttons["shared.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.buttons["shared.receipt"].waitForExistence(timeout: 10))
        XCTAssertFalse(send.isEnabled, "never replay the same text while its result is unknown")
        let notice = app.staticTexts["shared.send.disabledReason"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertTrue(notice.label.contains("结果尚未确认"))
        input.tap(); input.typeText(" -- genuinely new follow-up")
        XCTAssertTrue(send.isEnabled, "editing to a different message must release the gray Send button")
        send.tap()
        wait("label CONTAINS '发送请求：2'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(app.buttons["shared.receipt"].exists, "the first unknown receipt remains queryable")
    }
    func testStopAndUncertainSendCanCoexistWithoutPermanentlyGrayFollowUp() throws {
        let app = launch("--shared-fixture-stop-and-unknown-send")
        let stop = app.buttons["shared.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        XCTAssertTrue(stop.isEnabled)
        let input = composer(app)
        input.tap(); input.typeText("uncertain during generation")
        let send = app.buttons["shared.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.buttons["shared.receipt"].waitForExistence(timeout: 10))
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(stop.isEnabled, "uncertain Send must not block a separately observed PC Stop")
        input.tap(); input.typeText(" -- next distinct input")
        XCTAssertTrue(send.isEnabled, "Stop and a new eligible Send are independent")
        send.tap()
        wait("label CONTAINS '发送请求：2'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("中止请求：0"))
        XCTAssertTrue(app.buttons["shared.receipt"].exists)
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
    func testHomeDirectProductionEndpointAndNoCloudflareStageShortcut() throws {
        let app = launch()
        app.buttons["更多"].tap()
        let settings = app.buttons["连接设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let endpoint = app.textFields["HTTPS 服务地址"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 8))
        // UI-testing fixture must stay isolated; the release destination is
        // displayed independently and is verified by the native policy tests.
        XCTAssertEqual(endpoint.value as? String, "https://shared-tab.invalid")
        XCTAssertFalse(app.buttons["shared.useTestBridge"].exists)
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'https://chatgpt-pc.781751.xyz:58443'")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '127.0.0.1:13213/local/pair'")
        ).firstMatch.exists)
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testRunningPCWithDisabledNativeSendAllowsPhoneFollowUp() throws {
        let app = launch("--shared-fixture-busy-blocked")
        let input = composer(app)
        input.tap(); input.typeText("phone follow-up owns composer")
        XCTAssertTrue(app.buttons["shared.send"].isEnabled)
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.staticTexts["原生回复：phone follow-up owns composer"].waitForExistence(timeout: 10))
        wait("label CONTAINS '发送请求：1'", on: app.staticTexts["shared.fixture.counters"])
    }
    func testParkedPCDraftWithDisabledNativeControlsNeverBlocksPhoneSend() throws {
        let app = launch("--shared-fixture-pc-draft-native-blocked")
        let input = composer(app)
        input.tap(); input.typeText("phone draft only")
        XCTAssertTrue(app.buttons["shared.send"].isEnabled)
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.staticTexts["原生回复：phone draft only"].waitForExistence(timeout: 10))
        wait("label CONTAINS '发送请求：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertFalse(String(describing: composer(app).value).contains("PC parked draft"))
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
    func testNativeStopReplacesSendAndRestoresItAfterPCStops() throws {
        let app = launch("--shared-fixture-native-stop")
        let stop = app.buttons["shared.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        XCTAssertTrue(stop.isEnabled)
        XCTAssertFalse(app.buttons["shared.send"].exists)
        stop.tap()
        wait("label CONTAINS '中止请求：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(app.buttons["shared.send"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["shared.stop"].exists)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testGeneratingPCOffersStopAndIndependentPhoneFollowUpSend() throws {
        let app = launch("--shared-fixture-native-stop")
        XCTAssertTrue(app.buttons["shared.stop"].waitForExistence(timeout: 8))
        let input = composer(app)
        input.tap(); input.typeText("mobile follow up while PC generates")
        XCTAssertTrue(app.buttons["shared.send"].isEnabled)
        XCTAssertTrue(app.buttons["shared.stop"].isEnabled)
        app.buttons["shared.send"].tap()
        XCTAssertTrue(app.staticTexts["原生回复：mobile follow up while PC generates"].waitForExistence(timeout: 10))
        wait("label CONTAINS '发送请求：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("中止请求：0"))
        XCTAssertTrue(app.buttons["shared.stop"].exists)
    }
    func testStaleNativeStopNeverClicksAnotherGeneration() throws {
        let app = launch("--shared-fixture-stale-stop")
        let stop = app.buttons["shared.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8)); stop.tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("中止请求：0"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
        XCTAssertFalse(app.buttons["shared.receipt"].exists)
    }
    func testUnknownStopKeepsReceiptAndNeverRepeatsTheNativeClick() throws {
        let app = launch("--shared-fixture-stop-unknown")
        let stop = app.buttons["shared.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8)); stop.tap()
        let receipt = app.buttons["shared.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["shared.stop"].isEnabled)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("中止请求：1"))
        receipt.tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("中止请求：1"))
        XCTAssertFalse(app.buttons["shared.stop"].isEnabled)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testRunningWithoutPCStopControlNeverInventsStopButton() throws {
        let app = launch("--shared-fixture-busy-send")
        XCTAssertTrue(app.staticTexts["生成中"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["shared.stop"].exists)
        XCTAssertTrue(app.buttons["shared.send"].exists)
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
        picker.press(forDuration: 0.65)
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
    func testQuickPickerTapEffortLongPressModelWithoutSend() throws {
        let app = launch()
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        XCTAssertTrue(app.buttons["shared.model.fixture-effort-option-high"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["shared.model.fixture-model-option-0001"].exists)
        XCTAssertFalse(app.buttons["shared.model.fixture-model-option-gpt4o"].exists,
                       "Tap must open effort only")
        app.buttons["完成"].tap()
        picker.press(forDuration: 0.65)
        XCTAssertTrue(app.buttons["shared.model.fixture-model-option-gpt4o"].waitForExistence(timeout: 8),
                      "Long press must open the PC model list")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testQuickTapOpensNestedPCEffortDirectly() throws {
        let app = launch("--shared-fixture-nested-effort-submenu")
        let picker = app.buttons["shared.modelPicker"]
        picker.tap()
        let medium = app.buttons["shared.model.fixture-effort-medium"]
        XCTAssertTrue(medium.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["shared.model.fixture-option-gpt6-thinking"].exists)
        medium.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '已在 PC 网页选择'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testCompactEffortPickerBesideSend() throws {
        let app = launch()
        let picker = app.buttons["shared.modelPicker"]
        let send = app.buttons["shared.send"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertTrue(send.exists)
        XCTAssertLessThan(abs(picker.frame.midY - send.frame.midY), 46,
                          "Circular effort picker must sit beside Send")
        XCTAssertTrue(picker.label.contains("GPT-6"))
        XCTAssertTrue(picker.label.contains("High"))
        XCTAssertFalse(app.staticTexts["shared.header.modelName"].exists)
        picker.tap()
        let currentModel = app.staticTexts["shared.picker.currentModel"]
        XCTAssertTrue(currentModel.waitForExistence(timeout: 8))
        XCTAssertEqual(currentModel.label, "GPT-6")
        let currentEffort = app.staticTexts["shared.picker.currentEffort"]
        XCTAssertTrue(currentEffort.waitForExistence(timeout: 8))
        XCTAssertEqual(currentEffort.label, "High")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testUnknownEffortClearlyDisplaysUnconfirmed() throws {
        let app = launch("--shared-fixture-model-effort-unknown")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertTrue(picker.label.contains("强度未确认"))
        picker.tap()
        let currentEffort = app.staticTexts["shared.picker.currentEffort"]
        XCTAssertTrue(currentEffort.waitForExistence(timeout: 8))
        XCTAssertEqual(currentEffort.label, "强度未确认")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testNonThinkingModelDisplaysNotApplicable() throws {
        let app = launch("--shared-fixture-model-non-thinking")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertTrue(picker.label.contains("GPT-4o"))
        XCTAssertTrue(picker.label.contains("无独立强度/不适用"))
        picker.tap()
        let currentEffort = app.staticTexts["shared.picker.currentEffort"]
        XCTAssertTrue(currentEffort.waitForExistence(timeout: 8))
        XCTAssertEqual(currentEffort.label, "无独立强度/不适用")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testDynamicModelSelectionUpdatesSnapshotWithEvidence() throws {
        let app = launch()
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.press(forDuration: 0.65)
        let gpt4o = app.buttons["shared.model.fixture-model-option-gpt4o"]
        XCTAssertTrue(gpt4o.waitForExistence(timeout: 8))
        gpt4o.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '已在 PC 网页选择'")).firstMatch.waitForExistence(timeout: 8))
        wait("label CONTAINS 'GPT-4o'", on: picker, timeout: 8)
        XCTAssertTrue(picker.label.contains("无独立强度/不适用"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testNestedSubmenuForThinkingEffortLevels() throws {
        let app = launch("--shared-fixture-nested-effort-submenu")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.press(forDuration: 0.65)
        let thinkingSubmenu = app.buttons["shared.model.fixture-option-gpt6-thinking"]
        XCTAssertTrue(thinkingSubmenu.waitForExistence(timeout: 8))
        thinkingSubmenu.tap()
        let mediumOption = app.buttons["shared.model.fixture-effort-medium"]
        XCTAssertTrue(mediumOption.waitForExistence(timeout: 8))
        mediumOption.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '已在 PC 网页选择'")).firstMatch.waitForExistence(timeout: 8))
        wait("label CONTAINS 'Medium'", on: picker, timeout: 8)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testEffortListWithDynamicMinMaxAndValue() throws {
        let app = launch("--shared-fixture-effort-slider")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        XCTAssertTrue(app.staticTexts["shared.picker.currentEffort"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.sliders["shared.slider.fixture-slider-effort"].exists)
        // Only the four directly observed PC choices are shown; no guessed Pro.
        let low = app.buttons["shared.model.fixture-effort-level-1"]
        let medium = app.buttons["shared.model.fixture-effort-level-2"]
        let high = app.buttons["shared.model.fixture-effort-level-3"]
        let extra = app.buttons["shared.model.fixture-effort-level-4"]
        XCTAssertTrue(low.waitForExistence(timeout: 8))
        XCTAssertTrue(medium.isEnabled)
        XCTAssertTrue(high.isEnabled)
        XCTAssertTrue(extra.isEnabled)
        XCTAssertFalse(app.buttons["shared.effort.pro"].exists)
        high.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '已在 PC 网页选择'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("模型选择：1"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testOptionClickedWithoutSelectionObservedShowsUnconfirmed() throws {
        let app = launch("--shared-fixture-option-clicked-unobserved")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.press(forDuration: 0.65)
        let option = app.buttons["shared.model.fixture-model-option-0001"]
        XCTAssertTrue(option.waitForExistence(timeout: 8))
        option.tap()
        let notice = app.staticTexts["shared.picker.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertTrue(notice.label.contains("未确认 PC 已切换选项"))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '已在 PC 网页选择'")).firstMatch.exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testModelSelectTimeoutOr504DoesNotRetryPostAndKeepsReceipt() throws {
        let app = launch("--shared-fixture-model-select-timeout")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.press(forDuration: 0.65)
        let option = app.buttons["shared.model.fixture-model-option-0001"]
        XCTAssertTrue(option.waitForExistence(timeout: 8))
        option.tap()
        let notice = app.staticTexts["shared.picker.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertTrue(notice.label.contains("选择结果待确认") && notice.label.contains("不会自动重试"))
        wait("label CONTAINS '模型选择：1'", on: app.staticTexts["shared.fixture.counters"])
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.status"].label.contains("选择结果待确认"))
    }
    func testPCOnlineModelSwitchAutomaticallyUpdatesPhoneWithoutUserAction() throws {
        let app = launch("--shared-fixture-pc-model-switch")
        let modelLabel = app.buttons["shared.modelPicker"]
        XCTAssertTrue(modelLabel.waitForExistence(timeout: 8))
        XCTAssertTrue(modelLabel.label.contains("GPT-6"))
        // Simulate the PC side updating the model AFTER the initial iOS
        // snapshot is displayed. No phone model_select or Send is issued.
        let pcChanged = app.buttons["shared.fixture.pcModelChange"]
        XCTAssertTrue(pcChanged.waitForExistence(timeout: 8))
        pcChanged.tap()
        wait("label CONTAINS 'GPT-4o'", on: modelLabel, timeout: 15)
        XCTAssertTrue(modelLabel.label.contains("无独立强度/不适用"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("模型选择：0"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testModelSwitchPreservesPhoneDraftAndSendState() throws {
        let app = launch()
        let input = composer(app)
        input.tap()
        input.typeText("local draft stays untouched across model change")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.press(forDuration: 0.65)
        let high = app.buttons["shared.model.fixture-model-option-0001"]
        XCTAssertTrue(high.waitForExistence(timeout: 8))
        high.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '已在 PC 网页选择'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(String(describing: composer(app).value).contains("local draft stays untouched across model change"))
        XCTAssertTrue(app.buttons["shared.send"].isEnabled)
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testDisabledModelOptionCannotBeSelected() throws {
        let app = launch("--shared-fixture-option-disabled")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.press(forDuration: 0.65)
        let disabledOption = app.buttons["shared.model.fixture-option-disabled-pro"]
        XCTAssertTrue(disabledOption.waitForExistence(timeout: 8))
        XCTAssertFalse(disabledOption.isEnabled)
        XCTAssertTrue(disabledOption.label.contains("当前账号不可用"))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testPCFinishedRecoversStaleLoadingWithoutReplayingSend() throws {
        let app = launch("--shared-fixture-pc-done-loading")
        let refresh = app.buttons["shared.loading.refresh"]
        if refresh.exists { refresh.tap() }
        let input = composer(app)
        input.tap()
        input.typeText("fresh message after PC completed")
        let send = app.buttons["shared.send"]
        wait("enabled == true", on: send, timeout: 12)
        XCTAssertFalse(app.staticTexts["PC 页面加载中"].exists)
        send.tap()
        XCTAssertTrue(app.staticTexts["原生回复：fresh message after PC completed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：1"))
    }
    private func launchLong(_ extra: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--shared-tab-fixture", "--shared-fixture-long"] + (extra.map { [$0] } ?? [])
        app.launch()
        let tailAnswer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '长对话回答 第 15 轮'")).firstMatch
        XCTAssertTrue(tailAnswer.waitForExistence(timeout: 15))
        XCTAssertEqual(app.webViews.count, 0)
        return app
    }
    func testOpenLongChatPositionsLatestAnswerInViewport() throws {
        let app = launchLong()
        let transcript = app.scrollViews["shared.transcript"].frame
        let editor = composer(app).frame
        let latestAnswer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '长对话回答 第 15 轮'")).firstMatch
        XCTAssertTrue(latestAnswer.waitForExistence(timeout: 8))
        XCTAssertTrue(latestAnswer.isHittable || (latestAnswer.frame.maxY <= editor.minY + 20 && latestAnswer.frame.minY >= transcript.minY))
        XCTAssertLessThanOrEqual(latestAnswer.frame.minY, editor.minY)
        XCTAssertGreaterThanOrEqual(latestAnswer.frame.maxY, transcript.minY)
    }
    func testSendFollowsNewLatestMessageToVisibleTail() throws {
        let app = launchLong()
        let input = composer(app)
        input.tap()
        input.typeText("new tail question")
        let send = app.buttons["shared.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let reply = app.staticTexts["原生回复：new tail question"]
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        let transcript = app.scrollViews["shared.transcript"].frame
        let editor = composer(app).frame
        XCTAssertTrue(reply.isHittable || (reply.frame.maxY <= editor.minY + 20 && reply.frame.minY >= transcript.minY))
        XCTAssertLessThanOrEqual(reply.frame.minY, editor.minY)
        wait("label CONTAINS '发送请求：1'", on: app.staticTexts["shared.fixture.counters"])
    }
    func testManualHistoryScrollPausesAndResumeReturnsToLatest() throws {
        let app = launchLong()
        let transcript = app.scrollViews["shared.transcript"]
        transcript.swipeDown()
        let resumeButton = app.buttons["回到最新消息"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 8))
        resumeButton.tap()
        wait("exists == false", on: resumeButton, timeout: 6)
        let latestAnswer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '长对话回答 第 15 轮'")).firstMatch
        XCTAssertTrue(latestAnswer.waitForExistence(timeout: 8))
        let editor = composer(app).frame
        XCTAssertTrue(latestAnswer.isHittable || latestAnswer.frame.maxY <= editor.minY + 20)
    }
    func testShortChatViewportPositionsAnswerAboveComposerWithoutHugeOverscroll() throws {
        let app = launch()
        let answer = app.staticTexts["原生测试答案 A"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        XCTAssertTrue(answer.isHittable)
        let transcript = app.scrollViews["shared.transcript"].frame
        let editor = composer(app).frame
        XCTAssertGreaterThanOrEqual(answer.frame.minY, transcript.minY - 10)
        XCTAssertLessThanOrEqual(answer.frame.maxY, editor.minY)
        XCTAssertLessThan(answer.frame.minY, transcript.minY + transcript.height * 0.6)
    }
    func testSidebarPriorityTopSectionsRunningAndUnreadOrder() throws {
        let app = launch("--shared-fixture-sidebar")
        app.buttons["shared.sidebar"].tap()
        let runningHeader = app.staticTexts["进行中"]
        let unreadHeader = app.staticTexts["未读"]
        let recentHeader = app.staticTexts["最近活跃（含项目对话）"]
        XCTAssertTrue(runningHeader.waitForExistence(timeout: 8))
        XCTAssertTrue(unreadHeader.waitForExistence(timeout: 8))
        XCTAssertTrue(recentHeader.waitForExistence(timeout: 8))
        XCTAssertLessThan(runningHeader.frame.minY, unreadHeader.frame.minY)
        XCTAssertLessThan(unreadHeader.frame.minY, recentHeader.frame.minY)
        let runningChat = app.buttons["shared.chat.22222222-2222-4222-8222-222222222222"].firstMatch
        XCTAssertTrue(runningChat.exists)
        XCTAssertEqual(runningChat.value as? String, "生成中")
        let unreadChat = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(unreadChat.exists)
        XCTAssertEqual(unreadChat.value as? String, "未读")
    }
    func testSidebarRunningTakesPrecedenceOverUnreadWithoutDuplicate() throws {
        let app = launch("--shared-fixture-sidebar-both")
        app.buttons["shared.sidebar"].tap()
        XCTAssertTrue(app.staticTexts["进行中"].waitForExistence(timeout: 8))
        let chatB = app.buttons.matching(identifier: "shared.chat.22222222-2222-4222-8222-222222222222")
        XCTAssertTrue(chatB.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(chatB.count, 1, "Chat running and unread must appear only once in priority sections")
        XCTAssertEqual(chatB.firstMatch.value as? String, "生成中")
    }
    func testSidebarPriorityIncludesProjectChat() throws {
        let app = launch("--shared-fixture-sidebar")
        app.buttons["shared.sidebar"].tap()
        XCTAssertTrue(app.staticTexts["进行中"].waitForExistence(timeout: 8))
        let runningChat = app.buttons["shared.chat.22222222-2222-4222-8222-222222222222"].firstMatch
        XCTAssertTrue(runningChat.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Project Alpha"].waitForExistence(timeout: 8))
        XCTAssertEqual(runningChat.value as? String, "生成中")
    }
    func testSidebarReadAckClearsUnreadImmediatelyOnOpen() throws {
        let app = launch("--shared-fixture-sidebar")
        app.buttons["shared.sidebar"].tap()
        let chatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(chatA.waitForExistence(timeout: 8))
        XCTAssertEqual(chatA.value as? String, "未读")
        chatA.tap()
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].waitForExistence(timeout: 8))
        app.buttons["shared.sidebar"].tap()
        let reloadedChatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(reloadedChatA.waitForExistence(timeout: 8))
        XCTAssertNotEqual(reloadedChatA.value as? String, "未读", "Opened chat unread dot must be cleared immediately")
    }
    func testSidebarReadAckPreventsStalePCUnreadReplay() throws {
        let app = launch("--shared-fixture-sidebar-read-ack")
        app.buttons["shared.sidebar"].tap()
        let chatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(chatA.waitForExistence(timeout: 8))
        chatA.tap()
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].waitForExistence(timeout: 8))
        app.buttons["shared.sidebar"].tap()
        let checkedChatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(checkedChatA.waitForExistence(timeout: 8))
        XCTAssertNotEqual(checkedChatA.value as? String, "未读", "Stale PC unread replay must remain suppressed by local acknowledgement")
    }
    func testSidebarUnreadReappearsOnNewPositiveEvent() throws {
        let app = launch("--shared-fixture-sidebar-new-unread")
        app.buttons["shared.sidebar"].tap()
        let unreadHeader = app.staticTexts["未读"]
        XCTAssertTrue(unreadHeader.waitForExistence(timeout: 8))
        let chatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(chatA.waitForExistence(timeout: 8))
        XCTAssertEqual(chatA.value as? String, "未读")
    }
    func testSidebarPriorityPreservesSearchIsolation() throws {
        let app = launch("--shared-fixture-sidebar")
        app.buttons["shared.sidebar"].tap()
        XCTAssertTrue(app.staticTexts["进行中"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["未读"].waitForExistence(timeout: 8))
        let searchInput = app.textFields["shared.search.input"]
        XCTAssertTrue(searchInput.waitForExistence(timeout: 5))
        searchInput.tap()
        searchInput.typeText("older")
        app.buttons["shared.search"].tap()
        XCTAssertTrue(app.staticTexts["搜索结果"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["进行中"].exists)
        XCTAssertFalse(app.staticTexts["未读"].exists)
    }
    func testSidebarReadAckCompatibleWithSavedCodable() throws {
        let app = launch("--shared-fixture-sidebar")
        app.buttons["shared.sidebar"].tap()
        let chatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(chatA.waitForExistence(timeout: 8))
        chatA.tap()
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].waitForExistence(timeout: 8))
        app.buttons["shared.sidebar"].tap()
        let openedA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(openedA.waitForExistence(timeout: 8))
        XCTAssertNotEqual(openedA.value as? String, "未读")
    }
    func testSidebarUnreadShowsGreenForCompletedAndBlueForOther() throws {
        let app = launch("--shared-fixture-sidebar-colors")
        app.buttons["shared.sidebar"].tap()
        XCTAssertTrue(app.staticTexts["未读"].waitForExistence(timeout: 8))
        let chatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        let chatD = app.buttons["shared.chat.44444444-4444-4444-8444-444444444444"].firstMatch
        XCTAssertTrue(chatA.waitForExistence(timeout: 8))
        XCTAssertTrue(chatD.waitForExistence(timeout: 8))
        XCTAssertEqual(chatA.value as? String, "未读")
        XCTAssertEqual(chatD.value as? String, "未读")
    }
    func testR35ReviewFixNewUnreadAfterAck() throws {
        let app = launch("--shared-fixture-sidebar-new-unread")
        app.buttons["shared.sidebar"].tap()
        let chatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(chatA.waitForExistence(timeout: 8))
        XCTAssertEqual(chatA.value as? String, "未读")
        chatA.tap()
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].waitForExistence(timeout: 8))
        app.buttons["shared.sidebar"].tap()
        let ackedChatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(ackedChatA.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["聊天"].waitForExistence(timeout: 5))
    }
    func testR35ReviewFixReadAckPairIsolation() throws {
        let app = launch("--shared-fixture-sidebar")
        app.buttons["shared.sidebar"].tap()
        let chatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(chatA.waitForExistence(timeout: 8))
        chatA.tap()
        XCTAssertTrue(app.staticTexts["原生测试答案 A"].waitForExistence(timeout: 8))
        app.buttons["更多"].tap()
        let settings = app.buttons["连接设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.textFields["HTTPS 服务地址"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testR35ReviewFixModelSelectNilEvidenceRemainsUnconfirmed() throws {
        let app = launch("--shared-fixture-model-select-nil-evidence")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        let option = app.buttons["shared.model.fixture-model-option-0001"]
        XCTAssertTrue(option.waitForExistence(timeout: 8))
        option.tap()
        let notice = app.staticTexts["shared.picker.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertTrue(notice.label.contains("选择结果待确认"))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '已在 PC 网页选择'")).firstMatch.exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.status"].label.contains("选择结果待确认"))
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("模型选择：1"))
    }
    func testR35ReviewFixThinkingExplicitUnobservedOverridesHigh() throws {
        let app = launch("--shared-fixture-model-thinking-unobserved-high")
        let picker = app.buttons["shared.modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertTrue(picker.label.contains("强度未确认"),
                      "observed=false must override model.name 'GPT-6 Thinking · High'")
        XCTAssertTrue(picker.exists)
        picker.tap()
        let currentEffort = app.staticTexts["shared.picker.currentEffort"]
        XCTAssertTrue(currentEffort.waitForExistence(timeout: 8))
        XCTAssertEqual(currentEffort.label, "强度未确认")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["shared.fixture.counters"].label.contains("发送请求：0"))
    }
    func testR35ReviewFixSidebarCompletedOverRunningInAllListPaths() throws {
        let app = launch("--shared-fixture-sidebar-completed-over-running")
        app.buttons["shared.sidebar"].tap()
        XCTAssertTrue(app.staticTexts["聊天"].waitForExistence(timeout: 8))
        let chatA = app.buttons["shared.chat.11111111-1111-4111-8111-111111111111"].firstMatch
        XCTAssertTrue(chatA.waitForExistence(timeout: 8))
        XCTAssertNotEqual(chatA.value as? String, "生成中", "snapshot completed must override stale catalog running spinner")
        XCTAssertFalse(app.staticTexts["进行中"].exists, "completed chat must not be placed in running group")
    }
}
