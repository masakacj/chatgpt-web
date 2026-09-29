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
                "ChatGPT Web 控制"
            ]

        XCTAssertTrue(
            button.waitForExistence(
                timeout: 10
            ),
            "Script floating control did not appear"
        )

        XCTAssertTrue(
            button.isHittable,
            "Script floating control is not hittable"
        )

        button.tap()

        let currentScript =
            app.staticTexts[
                "当前脚本"
            ]
        let latestScript =
            app.staticTexts[
                "最新脚本"
            ]

        XCTAssertTrue(
            currentScript.waitForExistence(
                timeout: 3
            ),
            "Script-owned current version row is missing"
        )

        XCTAssertTrue(
            latestScript.waitForExistence(
                timeout: 3
            ),
            "Script-owned latest version row is missing"
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
            "Initial single tap did not open the script panel"
        )

        button.tap()

        XCTAssertFalse(
            initialCacheAction.exists,
            "Second tap did not collapse the script panel"
        )

        XCTAssertTrue(
            button.isHittable,
            "Floating control stopped being hittable after collapsing the script panel"
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
            "Post-drag script panel is missing the cache action"
        )
    }
}
