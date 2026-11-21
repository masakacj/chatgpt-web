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
