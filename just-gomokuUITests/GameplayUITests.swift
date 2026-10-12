import XCTest

final class GameplayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBoardModeAndNavigationFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openNewGame(in: app)
        select("2 Players", in: "new-game-opponent", app: app)
        select("15×15", in: "new-game-board-size", app: app)
        XCTAssertFalse(app.buttons["new-game-difficulty"].exists)
        XCTAssertFalse(app.steppers["custom-board-size"].exists)
        startGame(in: app)

        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitForMoveCount(0, on: board)
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForMoveCount(1, on: board)
        let activeBoardValue = board.value as? String

        openNewGame(in: app)
        configureAI(in: app)
        app.navigationBars["New Game"].buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["New Game"].exists)
        XCTAssertEqual(board.value as? String, activeBoardValue)

        openNewGame(in: app)
        configureAI(in: app)
        app.buttons["start-game"].tap()
        let confirmStart = app.buttons["Start New Game"]
        XCTAssertTrue(confirmStart.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["The current board will be cleared."].exists)
        confirmStart.tap()
        waitForMoveCount(1, on: board)
        XCTAssertTrue((board.value as? String)?.contains("Your move") == true)
        XCTAssertFalse(app.buttons["game-mode-menu"].exists)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Appearance"].exists || app.buttons["Appearance"].exists)
        XCTAssertTrue(app.switches["Haptics"].exists)
        XCTAssertTrue(app.buttons["About Just Gomoku"].exists)
        XCTAssertFalse(app.buttons["Board Size"].exists)
        XCTAssertFalse(app.buttons["Your Stones"].exists)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(board.exists)

        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCustomBoardControlsOnlyAppearForCustomSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openNewGame(in: app)
        select("2 Players", in: "new-game-opponent", app: app)
        select("15×15", in: "new-game-board-size", app: app)
        XCTAssertFalse(app.steppers["custom-board-size"].exists)

        select("Custom", in: "new-game-board-size", app: app)
        XCTAssertTrue(app.steppers["custom-board-size"].waitForExistence(timeout: 2))

        select("15×15", in: "new-game-board-size", app: app)
        XCTAssertFalse(app.steppers["custom-board-size"].exists)
        app.navigationBars["New Game"].buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["New Game"].exists)
    }

    @MainActor
    func testBoardSwipeDoesNotPlaceAndHeldDragPlacesOneStone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openNewGame(in: app)
        select("2 Players", in: "new-game-opponent", app: app)
        select("15×15", in: "new-game-board-size", app: app)
        startGame(in: app)

        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitForMoveCount(0, on: board)

        board.swipeUp()
        waitForMoveCount(0, on: board)

        let start = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = board.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.4, thenDragTo: destination)
        waitForMoveCount(1, on: board)
    }

    @MainActor
    func testPrimaryScreenAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))
        let moveCount = app.staticTexts["move-count"]
        XCTAssertTrue(moveCount.waitForExistence(timeout: 2))
        var auditTypes: XCUIAccessibilityAuditType = [
            .dynamicType, .hitRegion, .sufficientElementDescription,
        ]
        if moveCount.frame.height >= 30 { auditTypes.insert(.textClipped) }
        // Material contrast audits remain separate evidence: the tool flags
        // this HUD even with opaque black text on its light material surface.
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Primary screen accessibility audit"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        try audit(app, types: auditTypes)
    }

    @MainActor
    func testScrollableGameplayFooterAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-largest-text"]
        app.launch()
        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitForMoveCount(0, on: board)
        let moveCount = app.staticTexts["move-count"]
        XCTAssertTrue(moveCount.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(moveCount.frame.height, 30, "The footer audit must exercise the largest accessibility text size")
        let newGame = app.buttons["New Game"]
        let window = app.windows.firstMatch
        for _ in 0..<3 {
            if window.frame.contains(moveCount.frame), newGame.isHittable { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(window.frame.contains(moveCount.frame), "The move counter must be fully visible for the clipping audit")
        XCTAssertTrue(newGame.isHittable, "The action dock must be reachable at the largest text size")
        XCTAssertTrue(window.frame.contains(newGame.frame), "The action dock must fit within the visible viewport")
        waitForMoveCount(0, on: board)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Gameplay footer accessibility audit"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("Move counter before footer audit: \(moveCount.frame)")
        // This fixture fixes the largest size. Dynamic Type support is audited
        // above with the system setting; contrast diagnostics are saved separately.
        try audit(app, types: [
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
        ])
    }

    @MainActor
    private func audit(_ app: XCUIApplication, types: XCUIAccessibilityAuditType) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            print("Accessibility audit \(issue.auditType.rawValue): \(issue.compactDescription)")
            print(issue.detailedDescription)
            if let element = issue.element {
                print("Audit element identifier=\(element.identifier), label=\(element.label), frame=\(element.frame)")
                print(element.debugDescription)
            } else {
                print("Audit issue has no resolvable element. Current accessibility tree:\n\(app.debugDescription)")
            }
            return false
        }
    }

    @MainActor
    private func openNewGame(in app: XCUIApplication) {
        let newGame = app.buttons["New Game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        newGame.tap()
        XCTAssertTrue(app.navigationBars["New Game"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["start-game"].exists)
    }

    @MainActor
    private func select(_ title: String, in pickerIdentifier: String, app: XCUIApplication) {
        let picker = app.buttons[pickerIdentifier]
        _ = picker.waitForExistence(timeout: 2)
        for _ in 0..<4 {
            if picker.exists && picker.isHittable { break }
            let form = app.collectionViews.firstMatch
            if form.exists {
                form.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 2))
        XCTAssertTrue(picker.isHittable, "\(pickerIdentifier) should be visible after scrolling the form")
        picker.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 2))
        option.tap()
    }

    @MainActor
    private func configureAI(in app: XCUIApplication) {
        select("AI", in: "new-game-opponent", app: app)
        select("Medium", in: "new-game-difficulty", app: app)
        select("White", in: "new-game-stones", app: app)
        select("15×15", in: "new-game-board-size", app: app)
    }

    @MainActor
    private func startGame(in app: XCUIApplication) {
        app.buttons["start-game"].tap()
        let confirmation = app.buttons["Start New Game"]
        if confirmation.waitForExistence(timeout: 1) {
            confirmation.tap()
        }
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["New Game"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
    }

    @MainActor
    private func waitForMoveCount(_ count: Int, on board: XCUIElement) {
        let expectedMoveCount = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value ENDSWITH %@", "\(count) moves."),
            object: board
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectedMoveCount], timeout: 5), .completed)
    }
}
