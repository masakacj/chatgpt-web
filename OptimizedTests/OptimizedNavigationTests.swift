import XCTest
import Combine
import WebKit
@testable import ChatGPTWebOptimized

@MainActor
final class OptimizedNavigationTests: XCTestCase {
    func testBackStateAndHandlerAreInvalidatedWhenWebContentTerminates() {
        let model = OptimizedAppModel()
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)

        var backCalls = 0
        var forwardCalls = 0
        model.goBackHandler = { backCalls += 1 }
        model.goForwardHandler = { forwardCalls += 1 }
        model.setCanGoBack(true)
        model.setCanGoForward(true)
        model.goBack()
        model.goForward()
        XCTAssertTrue(model.canGoBack)
        XCTAssertTrue(model.canGoForward)
        XCTAssertEqual(backCalls, 1)
        XCTAssertEqual(forwardCalls, 1)

        model.markProcessTerminated(route: "project")
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
        model.goBack()
        model.goForward()
        XCTAssertEqual(backCalls, 1, "Dead WebView cannot receive back action")
        XCTAssertEqual(forwardCalls, 1, "Dead WebView cannot receive forward action")
    }

    func testCacheCheckWithoutWebViewDoesNotNavigateOrCreateWebView() async {
        let model = OptimizedAppModel()
        let originalGeneration = model.webViewGeneration
        await model.inspectFrameworkResourceCache()
        XCTAssertEqual(model.frameworkCacheReport, "网页未就绪")
        XCTAssertFalse(model.frameworkCacheChecking)
        XCTAssertEqual(model.webViewGeneration, originalGeneration)
        XCTAssertFalse(model.processTerminated)
    }

    func testWebHealthWithoutLoadedPageIsPassiveAndRecoveryIsExplicit() {
        let model = OptimizedAppModel()
        let generation = model.webViewGeneration
        XCTAssertFalse(model.checkWebContentHealth())
        XCTAssertFalse(model.webPageUnresponsive)
        XCTAssertEqual(model.webViewGeneration, generation)

        model.rebuildAfterConfirmation()
        XCTAssertNotEqual(model.webViewGeneration, generation)
        XCTAssertFalse(model.webPageUnresponsive)
        XCTAssertEqual(model.targetURL.absoluteString, "https://chatgpt.com/")
    }

    func testRebuildCurrentConversationKeepsProjectRouteWithoutReplayingActions() {
        let model = OptimizedAppModel()
        let original = model.webViewGeneration
        XCTAssertFalse(model.rebuildAfterConfirmation(destination: .currentConversation))
        XCTAssertEqual(model.webViewGeneration, original)

        let current = URL(string: "https://chatgpt.com/g/g-p-fixture/c/123456789012?source=old#turn")!
        model.rememberCurrentPage(current)
        let safe = "https://chatgpt.com/g/g-p-fixture/c/123456789012"
        XCTAssertEqual(model.currentConversationURL?.absoluteString, safe)
        XCTAssertTrue(model.rebuildAfterConfirmation(destination: .currentConversation))
        XCTAssertEqual(model.targetURL.absoluteString, safe)
        XCTAssertNotEqual(model.webViewGeneration, original)
        XCTAssertFalse(model.processTerminated)

        model.rememberCurrentPage(URL(string: "https://chatgpt.com/"))
        XCTAssertNil(model.currentConversationURL)
        XCTAssertFalse(model.rebuildAfterConfirmation(destination: .currentConversation))
    }

    func testCurrentConversationRebuildRejectsForeignHostsAndNonConversationPages() {
        XCTAssertNil(OptimizedAppModel.restorableConversationURL(
            URL(string: "https://other.example/c/123456789012")))
        XCTAssertNil(OptimizedAppModel.restorableConversationURL(
            URL(string: "http://chatgpt.com/c/123456789012")))
        XCTAssertNil(OptimizedAppModel.restorableConversationURL(
            URL(string: "https://chatgpt.com/g/g-p-fixture")))
        XCTAssertNil(OptimizedAppModel.restorableConversationURL(
            URL(string: "https://chatgpt.com/c/invalid")))
        XCTAssertEqual(OptimizedAppModel.restorableConversationURL(
            URL(string: "https://chatgpt.com/c/123456789012"))?.absoluteString,
            "https://chatgpt.com/c/123456789012")

        let model = OptimizedAppModel()
        model.rememberCurrentPage(URL(string: "https://chatgpt.com/c/123456789012"))
        model.rememberCurrentPage(nil)
        XCTAssertNotNil(model.currentConversationURL)
        model.rememberCurrentPage(URL(string: "https://external.example/"))
        XCTAssertNil(model.currentConversationURL)
        let unchanged = model.webViewGeneration
        XCTAssertFalse(model.rebuildAfterConfirmation(destination: .currentConversation))
        XCTAssertEqual(model.webViewGeneration, unchanged)

        model.rememberCurrentPage(URL(string: "https://chatgpt.com/g/g-p-fixture/c/123456789012"))
        model.markProcessTerminated(route: "project", isSynthetic: true)
        XCTAssertNotNil(model.currentConversationURL)
        XCTAssertTrue(model.rebuildAfterConfirmation(destination: .currentConversation))
        XCTAssertEqual(model.targetURL.path, "/g/g-p-fixture/c/123456789012")
    }

    func testWebHealthTimeoutDoesNotTreatBriefDelayAsFreeze() {
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(OptimizedAppModel.isWebHealthTimedOut(
            since: start, now: start.addingTimeInterval(14.9)))
        XCTAssertTrue(OptimizedAppModel.isWebHealthTimedOut(
            since: start, now: start.addingTimeInterval(15.1)))
    }

    func testNavigationResetDoesNotReleasePendingPingOnSameWebView() {
        let model = OptimizedAppModel()
        let first = WKWebView(frame: .zero)
        model.attachedWebView = first
        model.setPendingWebHealthProbeForTesting(first)
        model.resetWebContentHealth()
        XCTAssertTrue(model.hasPendingWebHealthProbeForTesting,
                      "Navigation cannot enqueue a second ping on a wedged WebContent")
        let replacement = WKWebView(frame: .zero)
        model.attachedWebView = replacement
        model.resetWebContentHealth()
        XCTAssertFalse(model.hasPendingWebHealthProbeForTesting,
                       "A new WebView must be independently probeable")
    }

    func testNavigationProbeAndHealthProbeDoNotOverlapOnSameView() {
        let model = OptimizedAppModel()
        let first = WKWebView(frame: .zero)
        model.attachedWebView = first
        XCTAssertTrue(model.beginNavigationJSProbe(on: first))
        XCTAssertFalse(model.beginNavigationJSProbe(on: first))
        model.resetWebContentHealth()
        XCTAssertTrue(model.hasPendingNavigationProbeForTesting)
        XCTAssertFalse(model.beginNavigationJSProbe(on: first))
        model.endNavigationJSProbe(on: first)
        XCTAssertTrue(model.beginNavigationJSProbe(on: first))
        model.endNavigationJSProbe(on: first)
        model.setPendingWebHealthProbeForTesting(first)
        XCTAssertFalse(model.beginNavigationJSProbe(on: first),
                       "An outstanding health ping blocks the older navigation probe")
        let replacement = WKWebView(frame: .zero)
        XCTAssertTrue(model.beginNavigationJSProbe(on: replacement))
        model.endNavigationJSProbe(on: first)
        XCTAssertTrue(model.hasPendingNavigationProbeForTesting)
        model.endNavigationJSProbe(on: replacement)
        XCTAssertFalse(model.hasPendingNavigationProbeForTesting)
    }

    func testRepeatedNavigationKVOValuesDoNotPublishUnchangedSwiftUIState() {
        let model = OptimizedAppModel()
        var backUpdates: [Bool] = []
        var forwardUpdates: [Bool] = []
        let a = model.$canGoBack.dropFirst().sink { backUpdates.append($0) }
        let b = model.$canGoForward.dropFirst().sink { forwardUpdates.append($0) }
        defer { a.cancel(); b.cancel() }

        for _ in 0..<15 {
            model.setCanGoBack(false)
            model.setCanGoForward(false)
        }
        XCTAssertTrue(backUpdates.isEmpty)
        XCTAssertTrue(forwardUpdates.isEmpty)
        model.setCanGoBack(true)
        model.setCanGoForward(true)
        model.setCanGoBack(true)
        model.setCanGoForward(true)
        XCTAssertEqual(backUpdates, [true])
        XCTAssertEqual(forwardUpdates, [true])
    }

    func testBackStateReflectsAvailabilityWithoutReloading() {
        let model = OptimizedAppModel()
        let initialGeneration = model.webViewGeneration
        model.setCanGoBack(true)
        model.setCanGoForward(true)
        model.setCanGoBack(false)
        model.setCanGoForward(false)
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
        XCTAssertEqual(model.webViewGeneration, initialGeneration)
    }
}
