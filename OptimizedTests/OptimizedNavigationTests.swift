import XCTest
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
