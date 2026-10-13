import XCTest

final class GameplayLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func record(_ issue: XCTIssue) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Gameplay layout failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        super.record(issue)
    }

    @MainActor
    func testBoardAndSectionEdgesStayFixedAcrossHintAndResultActions() {
        let app = launch(arguments: ["--ui-testing-win"])
        let board = app.otherElements["game-board"]
        waitForMoveCount(9, on: board)
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5))
        let playAgain = app.buttons["Play Again"]
        let undo = app.buttons["Undo"]
        XCTAssertTrue(playAgain.exists)
        // Establish an offset where both result controls can be tapped before
        // recording geometry. XCTest must not scroll implicitly during Undo.
        for _ in 0..<4 {
            if undo.isHittable, playAgain.isHittable { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(undo.isHittable)
        XCTAssertTrue(playAgain.isHittable)
        let completedFrame = board.frame
        assertSectionEdges(in: app, boardFrame: completedFrame)

        undo.tap()
        waitForMoveCount(8, on: board)
        XCTAssertFalse(app.buttons["Play Again"].exists)
        assertFrame(board.frame, equals: completedFrame, context: "Undoing a win")
        assertSectionEdges(in: app, boardFrame: completedFrame)

        let hint = app.buttons["Hint"]
        XCTAssertTrue(hint.isEnabled)
        hint.tap()
        // Hint calculation runs asynchronously with a 300 ms deadline. Observe
        // geometry through that interval, rather than only at the button tap.
        assertFrameStaysFixed(board, baseline: completedFrame, duration: 1)
        waitForMoveCount(8, on: board)

        board.coordinate(withNormalizedOffset: CGVector(dx: 4.5 / 9, dy: 0.5 / 9)).tap()
        waitForMoveCount(9, on: board)
        XCTAssertTrue(app.buttons["Play Again"].waitForExistence(timeout: 3))
        assertFrame(board.frame, equals: completedFrame, context: "Showing Play Again")
        assertSectionEdges(in: app, boardFrame: completedFrame)

        app.buttons["Play Again"].tap()
        waitForMoveCount(0, on: board)
        XCTAssertFalse(app.buttons["Play Again"].exists)
        assertFrame(board.frame, equals: completedFrame, context: "Restarting the game")
        assertSectionEdges(in: app, boardFrame: completedFrame)
    }

    @MainActor
    func testDismissingPrecisionTipKeepsBoardFrameAndSectionEdges() {
        let app = launch()
        openSettings(in: app)
        select("19×19", in: "settings-board-size", app: app)
        closeSettings(in: app)
        app.buttons["New Game"].tap()
        XCTAssertFalse(app.navigationBars["New Game"].exists)
        XCTAssertFalse(app.buttons["Start New Game"].exists)

        let board = app.otherElements["game-board"]
        waitForMoveCount(0, on: board)
        XCTAssertTrue(board.label.contains("19 by 19"))
        let initialBoardFrame = board.frame
        let controls = element("gameplay-controls", in: app)
        XCTAssertTrue(controls.waitForExistence(timeout: 3))
        let initialControlsFrame = controls.frame
        let gotIt = app.buttons["Got it"]
        XCTAssertTrue(gotIt.waitForExistence(timeout: 3))
        // On short screens the tip may need scrolling. Return to the same
        // initial offset before comparing screen coordinates.
        for _ in 0..<4 {
            if gotIt.isHittable { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(gotIt.isHittable)
        let boardFrameAtTip = board.frame
        let controlsFrameAtTip = controls.frame
        gotIt.tap()
        XCTAssertFalse(gotIt.exists)
        // Removing content must not clamp a short screen's scroll offset and
        // move the board. Compare before any deliberate scroll back to the top.
        assertFrame(controls.frame, equals: controlsFrameAtTip, context: "Keeping the current scroll offset after dismissing the precision tip")
        assertFrame(board.frame, equals: boardFrameAtTip, context: "Dismissing the precision tip at the current scroll offset")
        for _ in 0..<4 {
            if abs(controls.frame.minY - initialControlsFrame.minY) <= 1 { break }
            app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        }
        assertFrame(controls.frame, equals: initialControlsFrame, context: "Returning to the initial scroll offset")
        assertFrame(board.frame, equals: initialBoardFrame, context: "Dismissing the precision tip")
        assertSectionEdges(in: app, boardFrame: initialBoardFrame)
        waitForMoveCount(0, on: board)
    }

    @MainActor
    func testPlayAgainUsesSavedSettingsAndSettingsPreserveCompletedGame() {
        let app = launch(arguments: ["--ui-testing-win"])
        let board = app.otherElements["game-board"]
        waitForMoveCount(9, on: board)
        XCTAssertEqual(board.label, "Gomoku board, 9 by 9")
        let completedBoardValue = board.value as? String

        openSettings(in: app)
        select("2 Players", in: "settings-opponent", app: app)
        select("19×19", in: "settings-board-size", app: app)
        closeSettings(in: app)
        XCTAssertEqual(board.label, "Gomoku board, 9 by 9")
        XCTAssertEqual(board.value as? String, completedBoardValue,
                       "Saving next-game settings must preserve the completed game")
        let playAgain = app.buttons["Play Again"]
        XCTAssertTrue(playAgain.waitForExistence(timeout: 3))
        reveal(playAgain, in: app)
        playAgain.tap()
        waitForMoveCount(0, on: board)
        XCTAssertEqual(board.label, "Gomoku board, 19 by 19")
        XCTAssertFalse(app.buttons["Play Again"].exists)
        XCTAssertFalse(app.navigationBars["New Game"].exists)
        XCTAssertFalse(app.buttons["Start New Game"].exists)
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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        app.navigationBars["Settings"].buttons["Done"].tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Settings"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
    }

    @MainActor
    private func select(_ title: String, in identifier: String, app: XCUIApplication) {
        let picker = app.buttons[identifier]
        reveal(picker, in: app)
        picker.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 2))
        option.tap()
    }

    @MainActor
    private func reveal(_ control: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if control.exists && control.isHittable { break }
            let form = app.collectionViews.firstMatch
            if form.exists { form.swipeUp(velocity: .fast) }
            else { app.scrollViews.firstMatch.swipeUp(velocity: .fast) }
        }
        XCTAssertTrue(control.isHittable, "Control should be reachable after bounded scrolling")
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
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func assertSectionEdges(in app: XCUIApplication, boardFrame: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for identifier in ["match-hud", "match-dock"] {
            let section = element(identifier, in: app)
            XCTAssertTrue(section.waitForExistence(timeout: 3), "Missing \(identifier) layout container", file: file, line: line)
            XCTAssertEqual(section.frame.minX, boardFrame.minX, accuracy: 1, "\(identifier) leading edge", file: file, line: line)
            XCTAssertEqual(section.frame.maxX, boardFrame.maxX, accuracy: 1, "\(identifier) trailing edge", file: file, line: line)
        }
        let controls = element("gameplay-controls", in: app)
        XCTAssertTrue(controls.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(controls.frame.maxX, boardFrame.maxX, accuracy: 1, "Top controls trailing edge", file: file, line: line)
        let window = app.windows.firstMatch.frame
        if window.width < 736, window.width < window.height {
            XCTAssertEqual(boardFrame.minX - window.minX, 8, accuracy: 1, "Narrow phone leading margin", file: file, line: line)
            XCTAssertEqual(window.maxX - boardFrame.maxX, 8, accuracy: 1, "Narrow phone trailing margin", file: file, line: line)
        }
    }

    private func assertFrame(_ actual: CGRect, equals expected: CGRect, context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1, "\(context): board x", file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1, "\(context): board y", file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1, "\(context): board width", file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1, "\(context): board height", file: file, line: line)
    }

    @MainActor
    private func assertFrameStaysFixed(_ board: XCUIElement, baseline: CGRect, duration: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = board.frame
            return abs(frame.minX - baseline.minX) > 1
                || abs(frame.minY - baseline.minY) > 1
                || abs(frame.width - baseline.width) > 1
                || abs(frame.height - baseline.height) > 1
        }, object: board)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: duration), .completed, "Showing a hint must leave the board frame fixed", file: file, line: line)
    }

    @MainActor
    private func waitForMoveCount(_ count: Int, on board: XCUIElement) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value ENDSWITH %@", "\(count) moves."),
            object: board
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }
}
