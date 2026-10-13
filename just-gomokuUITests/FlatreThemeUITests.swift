import XCTest

final class FlatreThemeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFlatreThemePreservesCompletedBoardAndSelectionAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-win"]
        app.launchEnvironment["UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        assertBoardStatus("Black wins", on: board)
        XCTAssertFalse(app.buttons["theme-option-flatre"].exists)

        openThemes(in: app)
        let flatre = revealFlatreOption(in: app)
        XCTAssertTrue(flatre.label.contains("House"))
        XCTAssertTrue(flatre.label.contains("Key"))
        flatre.tap()
        assertSelected(flatre)
        attachScreenshot(named: "Flatre - Homes and Keys theme picker", in: app)
        closeSettings(in: app)

        assertBoardStatus("House (black side) wins", on: board)
        XCTAssertTrue(app.staticTexts["House wins"].firstMatch.waitForExistence(timeout: 3))
        attachScreenshot(named: "Flatre - Homes and Keys winning board", in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        assertBoardStatus("House (black side) wins", on: board)
        openThemes(in: app)
        assertSelected(revealFlatreOption(in: app))
        closeSettings(in: app)
        assertBoardStatus("House (black side) wins", on: board)
    }

    @MainActor
    private func openThemes(in app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let themes = app.buttons["settings-theme"]
        XCTAssertTrue(themes.waitForExistence(timeout: 3))
        themes.tap()
        XCTAssertTrue(app.navigationBars["Themes"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func revealFlatreOption(in app: XCUIApplication) -> XCUIElement {
        let flatre = app.buttons["theme-option-flatre"]
        for _ in 0..<6 {
            if flatre.exists && flatre.isHittable { break }
            let form = app.collectionViews.firstMatch
            if form.exists {
                form.swipeUp()
            } else if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(flatre.waitForExistence(timeout: 3))
        XCTAssertTrue(flatre.isHittable, "The Flatre option should be reachable in Everyday themes")
        return flatre
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        app.navigationBars["Themes"].buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.navigationBars["Settings"].buttons["Done"].tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Settings"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
    }

    @MainActor
    private func assertSelected(_ option: XCUIElement) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: option
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
    }

    @MainActor
    private func assertBoardStatus(_ status: String, on board: XCUIElement) {
        let unchangedCompletedGame = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@ AND value ENDSWITH %@", status, "9 moves."),
            object: board
        )
        XCTAssertEqual(XCTWaiter.wait(for: [unchangedCompletedGame], timeout: 5), .completed)
    }

    @MainActor
    private func attachScreenshot(named name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
