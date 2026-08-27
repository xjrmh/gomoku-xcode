import XCTest

final class GameplayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBoardModeAndNavigationFlow() throws {
        let app = XCUIApplication()
        app.launch()

        let newGame = app.buttons["New Game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        newGame.tap()
        let playerVsPlayer = app.buttons["Player vs Player"]
        XCTAssertTrue(playerVsPlayer.waitForExistence(timeout: 2))
        playerVsPlayer.tap()

        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let initialValue = board.value as? String
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertNotEqual(board.value as? String, initialValue)

        let gameMode = app.buttons["game-mode-menu"]
        XCTAssertTrue(gameMode.exists)
        gameMode.tap()
        let mediumAI = app.buttons["Medium"]
        XCTAssertTrue(mediumAI.waitForExistence(timeout: 2))
        mediumAI.tap()

        let aiMove = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "1 moves"),
            object: board
        )
        XCTAssertEqual(XCTWaiter.wait(for: [aiMove], timeout: 4), .completed)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Your Stones"].exists)
        app.buttons["Done"].tap()

        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testPrimaryScreenAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [
            .dynamicType,
            .hitRegion,
            .sufficientElementDescription,
        ])
    }
}
