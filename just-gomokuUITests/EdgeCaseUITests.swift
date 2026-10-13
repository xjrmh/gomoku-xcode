import XCTest

final class EdgeCaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func record(_ issue: XCTIssue) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Edge case failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: XCUIApplication().debugDescription)
        hierarchy.name = "Edge case accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        super.record(issue)
    }

    @MainActor
    func testDenseBoardRejectsOccupiedAndCancelledGesturesAndUndoesToEmpty() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("Custom", in: "settings-board-size", app: app)
        try setCustomBoardSize(25, in: app)
        let stepper = app.steppers["custom-board-size"]
        XCTAssertFalse(stepperButton("Increment", in: stepper).isEnabled)
        closeSettings(in: app)
        startNewGame(in: app)

        let board = app.otherElements["game-board"]
        assertBoardSize(25, on: board)
        waitForMoveCount(0, on: board)
        if app.buttons["Got it"].exists { app.buttons["Got it"].tap() }

        let center = intersection(row: 12, column: 12, size: 25, on: board)
        center.tap()
        waitForMoveCount(1, on: board)
        XCTAssertTrue((board.value as? String)?.contains("Cursor M13, Black.") == true)
        center.tap()
        waitForMoveCount(1, on: board)

        let emptyIntersection = intersection(row: 12, column: 15, size: 25, on: board)
        emptyIntersection.press(forDuration: 0.4)
        waitForMoveCount(2, on: board)

        let cancelledStart = intersection(row: 17, column: 12, size: 25, on: board)
        let aboveBoard = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.06))
        cancelledStart.press(forDuration: 0.4, thenDragTo: aboveBoard)
        waitForMoveCount(2, on: board)

        board.swipeUp()
        waitForMoveCount(2, on: board)

        app.buttons["Undo"].tap()
        waitForMoveCount(1, on: board)
        app.buttons["Undo"].tap()
        waitForMoveCount(0, on: board)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        XCTAssertTrue((board.value as? String)?.contains("Cursor M13, empty.") == true)
    }

    @MainActor
    func testSmallBoardSettingsPreserveCurrentGameAndNewGameImmediatelyResets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("9×9", in: "settings-board-size", app: app)
        closeSettings(in: app)
        startNewGame(in: app)

        let board = app.otherElements["game-board"]
        assertBoardSize(9, on: board)
        waitForMoveCount(0, on: board)
        intersection(row: 4, column: 4, size: 9, on: board).tap()
        waitForMoveCount(1, on: board)
        let activeBoardValue = board.value as? String

        openSettings(in: app)
        select("Custom", in: "settings-board-size", app: app)
        try setCustomBoardSize(5, in: app)
        XCTAssertFalse(stepperButton("Decrement", in: app.steppers["custom-board-size"]).isEnabled)
        closeSettings(in: app)
        assertBoardSize(9, on: board)
        XCTAssertEqual(board.value as? String, activeBoardValue,
                       "Changing saved settings must preserve the active board and turn")

        startNewGame(in: app)
        assertBoardSize(5, on: board)
        waitForMoveCount(0, on: board)
        XCTAssertTrue((board.value as? String)?.hasPrefix("Cursor C3, empty.") == true,
                      "A new board should reset its accessibility cursor to the new center")

        intersection(row: 0, column: 0, size: 5, on: board).tap()
        waitForMoveCount(1, on: board)
        intersection(row: 4, column: 4, size: 5, on: board).tap()
        waitForMoveCount(2, on: board)
        intersection(row: 0, column: 0, size: 5, on: board).tap()
        waitForMoveCount(2, on: board)

        startNewGame(in: app)
        assertBoardSize(5, on: board)
        waitForMoveCount(0, on: board)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        XCTAssertTrue((board.value as? String)?.hasPrefix("Cursor C3, empty.") == true)
    }

    @MainActor
    func testActiveGameResumesAfterRelaunchAndRemainsUndoable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("9×9", in: "settings-board-size", app: app)
        closeSettings(in: app)
        startNewGame(in: app)
        let board = app.otherElements["game-board"]
        assertBoardSize(9, on: board)
        waitForMoveCount(0, on: board)
        intersection(row: 4, column: 4, size: 9, on: board).tap()
        waitForMoveCount(1, on: board)
        intersection(row: 4, column: 5, size: 9, on: board).tap()
        waitForMoveCount(2, on: board)
        let activeBoardValue = board.value as? String

        app.terminate()
        app.launch()
        assertBoardSize(9, on: board)
        waitForMoveCount(2, on: board)
        XCTAssertEqual(board.value as? String, activeBoardValue,
                       "Relaunch should preserve the stones, turn, and active board size")
        app.buttons["Undo"].tap()
        waitForMoveCount(1, on: board)
        XCTAssertTrue((board.value as? String)?.contains("White's turn") == true)
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
        waitForDisappearance(of: app.navigationBars["Settings"])
    }

    @MainActor
    private func select(_ title: String, in identifier: String, app: XCUIApplication) {
        let picker = app.buttons[identifier]
        XCTAssertTrue(picker.waitForExistence(timeout: 2))
        reveal(picker, in: app)
        picker.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 2))
        option.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.isHittable { break }
            let form = app.collectionViews.firstMatch
            if form.exists { form.swipeUp() }
            else { app.scrollViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "Control should be reachable after bounded scrolling")
    }

    @MainActor
    private func stepperButton(_ action: String, in stepper: XCUIElement) -> XCUIElement {
        stepper.buttons.matching(NSPredicate(format: "label ENDSWITH %@", action)).firstMatch
    }

    @MainActor
    private func setCustomBoardSize(_ size: Int, in app: XCUIApplication) throws {
        let stepper = app.steppers["custom-board-size"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 2))
        var currentSize = try XCTUnwrap(Int(try XCTUnwrap(stepper.value as? String)))
        XCTAssertTrue((5...25).contains(currentSize) && !currentSize.isMultiple(of: 2))
        let increment = size > currentSize
        let button = stepperButton(increment ? "Increment" : "Decrement", in: stepper)
        XCTAssertTrue(button.exists)
        // iOS 18 exposes the native buttons as hit targets; its Stepper container has none.
        reveal(button, in: app)
        for _ in 0..<10 where currentSize != size {
            XCTAssertTrue(button.isEnabled, "Custom size control should allow the requested supported size")
            button.tap()
            currentSize += increment ? 2 : -2
            let updatedSize = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", String(currentSize)), object: stepper
            )
            XCTAssertEqual(XCTWaiter.wait(for: [updatedSize], timeout: 2), .completed)
        }
        XCTAssertEqual(stepper.value as? String, String(size))
    }

    @MainActor
    private func startNewGame(in app: XCUIApplication) {
        let newGame = app.buttons["New Game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        reveal(newGame, in: app)
        newGame.tap()
        XCTAssertFalse(app.navigationBars["New Game"].exists)
        XCTAssertFalse(app.buttons["start-game"].exists)
        XCTAssertFalse(app.buttons["Start New Game"].exists)
    }

    @MainActor
    private func intersection(row: Int, column: Int, size: Int, on board: XCUIElement) -> XCUICoordinate {
        board.coordinate(withNormalizedOffset: CGVector(
            dx: (CGFloat(column) + 0.5) / CGFloat(size),
            dy: (CGFloat(row) + 0.5) / CGFloat(size)
        ))
    }

    @MainActor
    private func assertBoardSize(_ size: Int, on board: XCUIElement) {
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.label, "Gomoku board, \(size) by \(size)")
    }

    @MainActor
    private func waitForMoveCount(_ count: Int, on board: XCUIElement) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value ENDSWITH %@", "\(count) moves."), object: board
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed,
                       "Expected \(count) moves; board reports \(board.value as? String ?? "no value")")
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement) {
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 3), .completed)
    }
}
