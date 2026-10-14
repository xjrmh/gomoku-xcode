import XCTest

final class GameplayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsNewGameImmediatelyAppliesSettingsToEmptyGame() throws {
        let app = launch()
        let board = app.otherElements["game-board"]
        waitForMoveCount(0, on: board)

        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("9×9", in: "settings-board-size", app: app)
        tapSettingsNewGame(in: app)

        waitForSettingsDismissal(in: app)
        XCTAssertFalse(app.alerts["Start a new game?"].exists,
                       "An empty game should apply Settings without a progress-loss confirmation")
        XCTAssertEqual(board.label, "Gomoku board, 9 by 9")
        waitForMoveCount(0, on: board)
        XCTAssertTrue(app.staticTexts["2 Players"].exists)
    }

    @MainActor
    func testSettingsNewGameCancelPreservesActiveGameAndConfirmationAppliesSettings() throws {
        let app = launch()
        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("15×15", in: "settings-board-size", app: app)
        closeSettings(in: app)
        startNewGame(in: app)

        let board = app.otherElements["game-board"]
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForMoveCount(1, on: board)
        let activeBoardValue = board.value as? String

        openSettings(in: app)
        select("AI", in: "settings-opponent", app: app)
        select("Easy", in: "settings-difficulty", app: app)
        select("White", in: "settings-stones", app: app)
        select("9×9", in: "settings-board-size", app: app)
        tapSettingsNewGame(in: app)

        let confirmation = app.alerts["Start a new game?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(confirmation.staticTexts["Your current game progress will be lost."].exists)
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists,
                      "Cancel must leave Settings open so the user can keep editing")
        assertSelection("9×9", in: "settings-board-size", app: app)
        closeSettings(in: app)
        XCTAssertEqual(board.label, "Gomoku board, 15 by 15")
        XCTAssertEqual(board.value as? String, activeBoardValue,
                       "Cancelling Settings New Game must preserve the current stones and turn")

        openSettings(in: app)
        tapSettingsNewGame(in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["New Game"].tap()
        waitForSettingsDismissal(in: app)
        XCTAssertFalse(confirmation.exists)
        XCTAssertEqual(board.label, "Gomoku board, 9 by 9")
        waitForMoveCount(1, on: board)
        XCTAssertTrue((board.value as? String)?.contains("Your move") == true,
                      "Starting as White must allow the AI to make the first black move")
        XCTAssertTrue(app.staticTexts["AI · Easy"].exists)
    }

    @MainActor
    func testSettingsNewGameImmediatelyAppliesSettingsToCompletedGame() throws {
        let app = launch(arguments: ["--ui-testing-win"])
        let board = app.otherElements["game-board"]
        waitForMoveCount(9, on: board)

        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("15×15", in: "settings-board-size", app: app)
        tapSettingsNewGame(in: app)

        waitForSettingsDismissal(in: app)
        XCTAssertFalse(app.alerts["Start a new game?"].exists,
                       "A completed game should apply Settings without a progress-loss confirmation")
        XCTAssertEqual(board.label, "Gomoku board, 15 by 15")
        waitForMoveCount(0, on: board)
        XCTAssertFalse(app.buttons["Play Again"].exists)
    }

    @MainActor
    func testNewGameUsesSettingsAfterConfirmationAndSettingsPreserveActiveBoard() throws {
        let app = launch()
        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("15×15", in: "settings-board-size", app: app)
        XCTAssertFalse(app.buttons["settings-difficulty"].exists)
        XCTAssertFalse(app.buttons["settings-stones"].exists)
        XCTAssertFalse(app.steppers["custom-board-size"].exists)
        closeSettings(in: app)
        startNewGame(in: app)

        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.label, "Gomoku board, 15 by 15")
        waitForMoveCount(0, on: board)
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForMoveCount(1, on: board)
        let activeBoardValue = board.value as? String

        openSettings(in: app)
        select("AI", in: "settings-opponent", app: app)
        select("Medium", in: "settings-difficulty", app: app)
        select("White", in: "settings-stones", app: app)
        select("19×19", in: "settings-board-size", app: app)
        closeSettings(in: app)
        XCTAssertEqual(board.label, "Gomoku board, 15 by 15")
        XCTAssertEqual(board.value as? String, activeBoardValue,
                       "Settings Done must preserve the current stones, turn, and board size")
        XCTAssertTrue(app.staticTexts["2 Players"].exists)

        startNewGame(in: app, confirmingProgressLoss: true)
        XCTAssertEqual(board.label, "Gomoku board, 19 by 19")
        waitForMoveCount(1, on: board)
        XCTAssertTrue((board.value as? String)?.contains("Your move") == true)
        XCTAssertTrue(app.staticTexts["AI · Medium"].exists)
        XCTAssertFalse(app.buttons["game-mode-menu"].exists)

        openSettings(in: app)
        reveal(app.buttons["settings-appearance"], in: app)
        XCTAssertTrue(app.buttons["settings-appearance"].exists)
        XCTAssertTrue(app.switches["Haptics"].exists)
        reveal(app.buttons["About Just Gomoku"], in: app)
        XCTAssertTrue(app.buttons["About Just Gomoku"].exists)
        closeSettings(in: app)
        XCTAssertTrue(board.exists)

        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testGameSettingsAutoSaveAcrossRelaunchBeforeDone() throws {
        let app = launch()
        let board = app.otherElements["game-board"]
        waitForMoveCount(0, on: board)
        let originalBoardSize = board.label
        let originalBoardValue = board.value as? String

        openSettings(in: app)
        select("AI", in: "settings-opponent", app: app)
        select("Easy", in: "settings-difficulty", app: app)
        select("White", in: "settings-stones", app: app)
        select("9×9", in: "settings-board-size", app: app)
        // Changes save as they are selected, even if the app exits before Done.
        app.terminate()
        app.launch()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.label, originalBoardSize)
        XCTAssertEqual(board.value as? String, originalBoardValue)

        openSettings(in: app)
        assertSelection("AI", in: "settings-opponent", app: app)
        assertSelection("Easy", in: "settings-difficulty", app: app)
        assertSelection("White", in: "settings-stones", app: app)
        assertSelection("9×9", in: "settings-board-size", app: app)
        closeSettings(in: app)
        XCTAssertEqual(board.label, originalBoardSize)
        XCTAssertEqual(board.value as? String, originalBoardValue)

        startNewGame(in: app)
        XCTAssertEqual(board.label, "Gomoku board, 9 by 9")
        waitForMoveCount(1, on: board)
        XCTAssertTrue((board.value as? String)?.contains("Your move") == true)
        XCTAssertTrue(app.staticTexts["AI · Easy"].exists)
    }

    @MainActor
    func testCustomBoardControlsOnlyAppearForCustomSelection() throws {
        let app = launch()
        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("15×15", in: "settings-board-size", app: app)
        XCTAssertFalse(app.steppers["custom-board-size"].exists)

        select("Custom", in: "settings-board-size", app: app)
        XCTAssertTrue(app.steppers["custom-board-size"].waitForExistence(timeout: 2))

        select("15×15", in: "settings-board-size", app: app)
        XCTAssertFalse(app.steppers["custom-board-size"].exists)
        closeSettings(in: app)
        waitForMoveCount(0, on: app.otherElements["game-board"])
    }

    @MainActor
    func testBoardSwipeDoesNotPlaceAndHeldDragPlacesOneStone() throws {
        let app = launch()
        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("15×15", in: "settings-board-size", app: app)
        closeSettings(in: app)
        startNewGame(in: app)

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
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        app.launchEnvironment["UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if settings.isHittable { break }
            app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(settings.isHittable, "Settings should be reachable after scrolling back to the gameplay header")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        app.navigationBars["Settings"].buttons["Done"].tap()
        waitForSettingsDismissal(in: app)
    }

    @MainActor
    private func tapSettingsNewGame(in app: XCUIApplication) {
        let newGame = app.buttons["settings-new-game"]
        reveal(newGame, in: app)
        newGame.tap()
    }

    @MainActor
    private func waitForSettingsDismissal(in app: XCUIApplication) {
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Settings"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
    }

    @MainActor
    private func startNewGame(in app: XCUIApplication, confirmingProgressLoss: Bool = false) {
        let newGame = app.buttons["New Game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        reveal(newGame, in: app)
        newGame.tap()
        let confirmation = app.alerts["Start a new game?"]
        if confirmingProgressLoss {
            XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
            XCTAssertTrue(confirmation.staticTexts["Your current game progress will be lost."].exists)
            confirmation.buttons["New Game"].tap()
        }
        XCTAssertFalse(confirmation.exists)
        XCTAssertFalse(app.navigationBars["New Game"].exists)
        XCTAssertFalse(app.buttons["start-game"].exists)
        XCTAssertFalse(app.buttons["Start New Game"].exists)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.exists && element.isHittable { break }
            let form = app.collectionViews.firstMatch
            if form.exists { form.swipeUp() }
            else { app.scrollViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "Control should be reachable after bounded scrolling")
    }

    @MainActor
    private func assertSelection(_ title: String, in identifier: String, app: XCUIApplication) {
        let picker = app.buttons[identifier]
        reveal(picker, in: app)
        let selection = picker.label + " " + (picker.value as? String ?? "")
        XCTAssertTrue(selection.contains(title), "\(identifier) should retain \(title); reports \(selection)")
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
    private func waitForMoveCount(_ count: Int, on board: XCUIElement) {
        let expectedMoveCount = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value ENDSWITH %@", "\(count) moves."),
            object: board
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectedMoveCount], timeout: 5), .completed)
    }
}
