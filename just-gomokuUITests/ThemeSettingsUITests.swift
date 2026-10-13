import XCTest

final class ThemeSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testThemeIsOptInThroughSettingsAndSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings-theme"].exists)
        XCTAssertFalse(app.buttons["theme-option-halloween"].exists)

        openThemes(in: app)
        assertSelected("standard", in: app)
        attachScreenshot(named: "Themes - Standard default", in: app)
        let halloween = app.buttons["theme-option-halloween"]
        XCTAssertTrue(halloween.waitForExistence(timeout: 2))
        halloween.tap()
        assertSelected("halloween", in: app)
        closeSettings(in: app)
        assertVisiblePlayerName("Pumpkin", in: app)
        attachScreenshot(named: "Halloween gameplay", in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))
        assertVisiblePlayerName("Pumpkin", in: app)
        openThemes(in: app)
        assertSelected("halloween", in: app)

        app.buttons["theme-option-standard"].tap()
        assertSelected("standard", in: app)
        closeSettings(in: app)
        assertVisiblePlayerName("Black", in: app)
        XCTAssertFalse(app.buttons["settings-theme"].exists)
        XCTAssertFalse(app.buttons["theme-option-standard"].exists)
    }

    @MainActor
    func testPastStandardGamesKeepTheirThemeAfterChoosingHalloween() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-history"]
        app.launchEnvironment["UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))

        selectTheme("halloween", in: app)
        assertVisiblePlayerName("Pumpkin", in: app)
        openHistory(in: app)
        let standardGame = historyCard(result: "Black won", in: app)
        XCTAssertTrue(standardGame.waitForExistence(timeout: 3))
        XCTAssertFalse(historyCard(result: "Pumpkin won", in: app).exists)
        attachScreenshot(named: "Standard history after selecting Halloween", in: app)

        standardGame.tap()
        XCTAssertTrue(app.navigationBars["Black won"].waitForExistence(timeout: 3))
        let replay = replayBoard(in: app)
        XCTAssertTrue(replay.waitForExistence(timeout: 3))
        XCTAssertTrue((replay.value as? String)?.contains("5 black stones and 4 white stones") == true)
        waitForReplayMove("Black at E1", in: app)
        app.buttons["Previous move"].tap()
        waitForReplayMove("White at D2", in: app)
        XCTAssertFalse((replay.value as? String)?.contains("Pumpkin") == true)
        attachScreenshot(named: "Standard replay after selecting Halloween", in: app)
    }

    @MainActor
    func testNewHalloweenGameKeepsItsThemeAfterReturningToStandard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-win"]
        app.launchEnvironment["UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()
        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitForMoveCount(9, on: board)

        let playAgain = app.buttons["Play Again"]
        for _ in 0..<3 {
            if playAgain.exists && playAgain.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(playAgain.waitForExistence(timeout: 3))
        playAgain.tap()
        waitForMoveCount(0, on: board)
        app.scrollViews.firstMatch.swipeDown()
        selectTheme("halloween", in: app)

        // Finish a real game so ContentView's completion callback must capture
        // the currently selected theme; the seed's earlier win remains Standard.
        for column in 0..<5 {
            tapCell(row: 0, column: column, on: board)
            waitForMoveCount(column * 2 + 1, on: board)
            if column < 4 {
                tapCell(row: 1, column: column, on: board)
                waitForMoveCount(column * 2 + 2, on: board)
            }
        }
        XCTAssertTrue((board.value as? String)?.contains("Pumpkin (black side) wins") == true)

        selectTheme("standard", in: app)
        openHistory(in: app)
        let halloweenGame = historyCard(result: "Pumpkin won", in: app)
        XCTAssertTrue(halloweenGame.waitForExistence(timeout: 3))
        XCTAssertTrue(historyCard(result: "Black won", in: app).exists)
        attachScreenshot(named: "Mixed Standard and Halloween history", in: app)

        halloweenGame.tap()
        XCTAssertTrue(app.navigationBars["Pumpkin won"].waitForExistence(timeout: 3))
        let replay = replayBoard(in: app)
        XCTAssertTrue(replay.waitForExistence(timeout: 3))
        XCTAssertTrue((replay.value as? String)?.contains("5 Pumpkin (black side) pieces and 4 Ghost (white side) pieces") == true)
        waitForReplayMove("Pumpkin at E1", in: app)
        app.buttons["Previous move"].tap()
        waitForReplayMove("Ghost at D2", in: app)
        attachScreenshot(named: "Halloween replay after selecting Standard", in: app)
    }

    @MainActor
    private func selectTheme(_ theme: String, in app: XCUIApplication) {
        openThemes(in: app)
        app.buttons["theme-option-\(theme)"].tap()
        assertSelected(theme, in: app)
        closeSettings(in: app)
    }

    @MainActor
    private func openHistory(in app: XCUIApplication) {
        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func historyCard(result: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", result)).firstMatch
    }

    @MainActor
    private func replayBoard(in app: XCUIApplication) -> XCUIElement {
        app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Replay board,")).firstMatch
    }

    @MainActor
    private func tapCell(row: Int, column: Int, on board: XCUIElement) {
        board.coordinate(withNormalizedOffset: CGVector(
            dx: (Double(column) + 0.5) / 9,
            dy: (Double(row) + 0.5) / 9
        )).tap()
    }

    @MainActor
    private func waitForMoveCount(_ count: Int, on board: XCUIElement) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value ENDSWITH %@", "\(count) moves."),
            object: board
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    @MainActor
    private func waitForReplayMove(_ summary: String, in app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", summary),
            object: app.sliders["Replay position"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 3), .completed)
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
    private func assertSelected(_ theme: String, in app: XCUIApplication) {
        let option = app.buttons["theme-option-\(theme)"]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: option
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
    }

    @MainActor
    private func assertVisiblePlayerName(_ name: String, in app: XCUIApplication) {
        let player = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 3), "The gameplay turn display should use \(name)")
    }

    @MainActor
    private func attachScreenshot(named name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
