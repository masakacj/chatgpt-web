import XCTest

final class ChatGPTWebUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFloatingControlIsVisibleDraggableAndHasCacheAction()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments.append(
            "--ui-testing"
        )
        app.launch()

        let button =
            app.buttons[
                "chatgpt.web.floatingControl"
            ]

        XCTAssertTrue(
            button.waitForExistence(
                timeout: 10
            ),
            "Native floating control did not appear"
        )

        XCTAssertTrue(
            button.isHittable,
            "Native floating control is not hittable"
        )

        button.tap()

        let currentVersion =
            app.staticTexts[
                "chatgpt.web.currentVersion"
            ]
        let latestVersion =
            app.staticTexts[
                "chatgpt.web.latestVersion"
            ]

        XCTAssertTrue(
            currentVersion.waitForExistence(
                timeout: 3
            ),
            "Compact current-version label is missing"
        )
        XCTAssertTrue(
            latestVersion.waitForExistence(
                timeout: 3
            ),
            "Compact latest-version label is missing"
        )

        let initialCacheAction =
            app.descendants(
                matching: .any
            )[
                "清除网页缓存（保留登录）"
            ]

        XCTAssertTrue(
            initialCacheAction.waitForExistence(
                timeout: 3
            ),
            "Initial single tap did not open the inline menu"
        )

        button.tap()

        XCTAssertFalse(
            initialCacheAction.exists,
            "Second tap did not collapse the inline menu"
        )

        XCTAssertTrue(
            button.isHittable,
            "Floating control stopped being hittable after collapsing the inline menu"
        )

        let initialFrame = button.frame

        let destination =
            app.coordinate(
                withNormalizedOffset:
                    CGVector(
                        dx: 0.38,
                        dy: 0.42
                    )
            )

        let start =
            button.coordinate(
                withNormalizedOffset:
                    CGVector(
                        dx: 0.5,
                        dy: 0.5
                    )
            )

        start.press(
            forDuration: 0.15,
            thenDragTo: destination
        )

        XCTAssertTrue(
            button.waitForExistence(
                timeout: 3
            )
        )

        let movedFrame = button.frame

        XCTAssertTrue(
            button.isHittable,
            "Floating control stopped being hittable after drag. Initial: \(initialFrame), moved: \(movedFrame), app: \(app.frame)"
        )
        let movement =
            abs(
                movedFrame.midX -
                initialFrame.midX
            ) +
            abs(
                movedFrame.midY -
                initialFrame.midY
            )

        XCTAssertGreaterThan(
            movement,
            20,
            "Floating control did not actually move"
        )

        button.tap()

        let cacheAction =
            app.descendants(
                matching: .any
            )[
                "清除网页缓存（保留登录）"
            ]

        XCTAssertTrue(
            cacheAction.waitForExistence(
                timeout: 3
            ),
            "Post-drag inline menu is missing the cache action"
        )
    }
}
