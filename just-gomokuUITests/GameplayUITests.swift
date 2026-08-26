import XCTest

final class GameplayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBoardModeAndNavigationFlow() throws {
        let app = XCUIApplication()
        app.launch()

        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let initialValue = board.value as? String
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertNotEqual(board.value as? String, initialValue)

        let aiMode = app.segmentedControls.firstMatch.buttons["AI"]
        XCTAssertTrue(aiMode.exists)
        aiMode.tap()
        XCTAssertTrue((board.value as? String)?.contains("1 moves") == true)

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
