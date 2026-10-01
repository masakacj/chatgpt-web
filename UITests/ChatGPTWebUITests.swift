import XCTest

final class ChatGPTWebUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFloatingControlIsVisibleAndDraggable()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments.append(
            "--ui-testing"
        )
        app.launch()

        let button =
            app.buttons[
                "chatgpt.web.floatingAnchor"
            ]

        XCTAssertTrue(
            button.waitForExistence(
                timeout: 10
            ),
            "Native anchor did not appear"
        )

        XCTAssertTrue(
            button.isHittable,
            "Native anchor is not hittable"
        )

        XCTAssertFalse(
            app.buttons[
                "ChatGPT Web 控制"
            ].exists,
            "Hybrid container should not expose the JS fallback S button"
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

        let dragStart =
            button.coordinate(
                withNormalizedOffset:
                    CGVector(
                        dx: 0.5,
                        dy: 0.5
                    )
            )

        dragStart.press(
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
            "Native anchor stopped being hittable after drag"
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
            "Native anchor did not actually move"
        )
    }

    func testNativeEdgeSidebarGestures()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments.append(
            "--ui-testing"
        )
        app.launch()

        let openButton =
            app.buttons["Open sidebar"]

        XCTAssertTrue(
            openButton.waitForExistence(
                timeout: 10
            ),
            "Sidebar probe button did not appear"
        )

        let leftStart =
            app.coordinate(
                withNormalizedOffset:
                    CGVector(
                        dx: 0.002,
                        dy: 0.56
                    )
            )
        let leftEnd =
            app.coordinate(
                withNormalizedOffset:
                    CGVector(
                        dx: 0.09,
                        dy: 0.56
                    )
            )

        leftStart.press(
            forDuration: 0.02,
            thenDragTo: leftEnd
        )

        XCTAssertTrue(
            app.buttons["Sidebar opened"]
                .waitForExistence(
                    timeout: 3
                ),
            "Left-edge swipe did not open the sidebar probe"
        )

        let rightStart =
            app.coordinate(
                withNormalizedOffset:
                    CGVector(
                        dx: 0.998,
                        dy: 0.56
                    )
            )
        let rightEnd =
            app.coordinate(
                withNormalizedOffset:
                    CGVector(
                        dx: 0.91,
                        dy: 0.56
                    )
            )

        rightStart.press(
            forDuration: 0.02,
            thenDragTo: rightEnd
        )

        XCTAssertTrue(
            app.buttons["Open sidebar"]
                .waitForExistence(
                    timeout: 3
                ),
            "Right-edge swipe did not close the sidebar probe"
        )
    }
}
