import XCTest
import Combine
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
