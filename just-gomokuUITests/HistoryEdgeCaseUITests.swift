import XCTest

/// The DEBUG-only fixtures isolate both the active game and the archive from user data.
/// `--ui-testing-history` supplies 40 completed 2 Players games, with a 25-move Draw newest.
final class HistoryEdgeCaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyArchiveUsesNoGamesMessage() {
        let app = launch()
        openHistory(in: app)
        XCTAssertTrue(app.staticTexts["No Games Yet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Completed games will appear here."].exists)
        XCTAssertFalse(app.staticTexts["No Matches"].exists)
    }

    @MainActor
    func testEmptyModeFilterDoesNotClaimArchiveIsEmpty() {
        let app = launch(scenario: "--ui-testing-history")
        openHistory(in: app)
        XCTAssertTrue(firstHistoryCard(in: app).waitForExistence(timeout: 3))

        app.buttons["AI"].tap()
        XCTAssertTrue(app.staticTexts["No Matches"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No Games Yet"].exists)

        app.buttons["All"].tap()
        XCTAssertTrue(firstHistoryCard(in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No Matches"].exists)
    }

    @MainActor
    func testSearchNoMatchesAndClearingRestoresArchive() {
        let app = launch(scenario: "--ui-testing-history")
        openHistory(in: app)
        let search = revealSearch(in: app)
        search.tap()
        search.typeText("edge-case-no-match")
        XCTAssertTrue(app.staticTexts["No Matches"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No Games Yet"].exists)

        clear(search, in: app)
        search.typeText("Draw")
        XCTAssertTrue(drawHistoryCard(in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No Matches"].exists)

        clear(search, in: app)
        XCTAssertTrue(firstHistoryCard(in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No Matches"].exists)
    }

    @MainActor
    func testSearchMatchesDisplayedBoardSizeAndASCIIAlias() {
        let app = launch(scenario: "--ui-testing-history")
        openHistory(in: app)
        let search = revealSearch(in: app)
        search.tap()
        search.typeText("15×15")
        let matchingCards = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "15×15"))
        XCTAssertTrue(matchingCards.firstMatch.waitForExistence(timeout: 3), "Searching the board size exactly as displayed on a card should find that game.")
        XCTAssertFalse(app.staticTexts["No Matches"].exists)

        clear(search, in: app)
        search.typeText("15x15")
        XCTAssertTrue(matchingCards.firstMatch.waitForExistence(timeout: 3), "The ASCII board-size alias should also find the same games.")
        XCTAssertFalse(app.staticTexts["No Matches"].exists)
    }

    @MainActor
    func testReplayClampsAtStartingAndFinalPositions() {
        let app = launch(scenario: "--ui-testing-history")
        openDrawReplay(in: app)

        XCTAssertTrue(app.staticTexts["Move 25 of 25"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Next move"].isEnabled)
        XCTAssertFalse(app.buttons["Final position"].isEnabled)
        app.buttons["Previous move"].tap()
        XCTAssertTrue(app.staticTexts["Move 24 of 25"].waitForExistence(timeout: 2))
        app.buttons["Final position"].tap()
        XCTAssertTrue(app.staticTexts["Move 25 of 25"].waitForExistence(timeout: 2))

        app.sliders["Replay position"].adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(app.staticTexts["Move 0 of 25"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Starting position"].exists)
        XCTAssertFalse(app.buttons["Previous move"].isEnabled)
        XCTAssertTrue(app.buttons["Next move"].isEnabled)
        app.buttons["Next move"].tap()
        XCTAssertTrue(app.staticTexts["Move 1 of 25"].waitForExistence(timeout: 2))
        app.buttons["Previous move"].tap()
        XCTAssertTrue(app.staticTexts["Move 0 of 25"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testReplayFromEndRestartsAndScrubbingPausesPlayback() {
        let app = launch(scenario: "--ui-testing-history")
        openDrawReplay(in: app)

        app.buttons["Play replay"].tap()
        XCTAssertTrue(app.buttons["Pause replay"].waitForExistence(timeout: 2))
        let position = app.sliders["Replay position"]
        // Playback advances every 600 ms; XCTest's snapshot polling can miss an individual move.
        let intermediateMove = "Move ([1-9]|1[0-9]|2[0-4]) of 25\\..*"
        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value MATCHES %@", intermediateMove),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 3), .completed)
        let firstPlaybackValue = position.value as? String ?? ""
        let advanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@ AND value MATCHES %@", firstPlaybackValue, intermediateMove),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 3), .completed)

        position.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(app.buttons["Play replay"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Pause replay"].exists)
        let pausedValue = position.value as? String
        XCTAssertNotNil(pausedValue)
        let continuedPlayback = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", pausedValue ?? ""),
            object: position
        )
        continuedPlayback.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [continuedPlayback], timeout: 1.3), .completed)
    }

    @MainActor
    func testDrawResultCanShareAndPlayAgainKeepsBoardSize() {
        let app = launch(scenario: "--ui-testing-draw")
        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue((board.value as? String)?.contains("Draw") == true)
        XCTAssertTrue((board.value as? String)?.hasSuffix("25 moves.") == true)
        XCTAssertTrue(app.buttons["Play Again"].exists)
        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        assertShareSheet(in: app, title: "Draw · 25 moves")

        // Relaunch restores the same isolated fixture and dismisses the system share sheet.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Play Again"].waitForExistence(timeout: 5))
        app.buttons["Play Again"].tap()
        let restartedBoard = app.otherElements["game-board"]
        XCTAssertTrue(restartedBoard.waitForExistence(timeout: 3))
        let reset = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value ENDSWITH %@", "0 moves."),
            object: restartedBoard
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 3), .completed)
        XCTAssertTrue(restartedBoard.label.contains("5 by 5"))
        XCTAssertFalse(app.buttons["Share"].exists)
        XCTAssertTrue(app.buttons["Hint"].exists)
    }

    @MainActor
    func testWinResultCanOpenSystemShareSheet() {
        let app = launch(scenario: "--ui-testing-win")
        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue((board.value as? String)?.contains("Black wins") == true)
        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        assertShareSheet(in: app, title: "Black wins · 9 moves")
    }

    @MainActor
    func testFinishedGameCanChangeAppearanceAndShareWithoutRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-win"]
        app.launchEnvironment["UI_TEST_RUN_ID"] = "share-appearance-\(UUID().uuidString)"
        app.launch()
        let board = app.otherElements["game-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let result = board.value as? String
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5))

        for appearance in ["Light", "Dark"] {
            app.buttons["Settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
            app.buttons["settings-appearance"].tap()
            XCTAssertTrue(app.buttons[appearance].waitForExistence(timeout: 2))
            app.buttons[appearance].tap()
            app.navigationBars["Settings"].buttons["Done"].tap()
            XCTAssertTrue(board.waitForExistence(timeout: 3))
            XCTAssertEqual(board.value as? String, result)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Finished game in \(appearance) appearance"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.buttons["Share"].tap()
        assertShareSheet(in: app, title: "Black wins · 9 moves")
    }

    @MainActor
    private func launch(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        if let scenario { app.launchArguments.append(scenario) }
        app.launch()
        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func openHistory(in app: XCUIApplication) {
        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func firstHistoryCard(in app: XCUIApplication) -> XCUIElement {
        let identified = app.buttons.matching(identifier: "history-game-card").firstMatch
        if identified.exists { return identified }
        return app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@", "Draw", "Black won", "White won")).firstMatch
    }

    @MainActor
    private func drawHistoryCard(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Draw")).firstMatch
    }

    @MainActor
    private func openDrawReplay(in app: XCUIApplication) {
        openHistory(in: app)
        let card = drawHistoryCard(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
        XCTAssertTrue(app.sliders["Replay position"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func revealSearch(in app: XCUIApplication) -> XCUIElement {
        let search = app.searchFields.firstMatch
        for _ in 0..<3 {
            if search.exists && search.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(search.isHittable)
        return search
    }

    @MainActor
    private func clear(_ search: XCUIElement, in app: XCUIApplication) {
        let clearButton = search.buttons["Clear text"]
        if clearButton.exists {
            clearButton.tap()
        } else {
            search.tap()
            let count = (search.value as? String)?.count ?? 0
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
    }

    @MainActor
    private func assertShareSheet(in app: XCUIApplication, title: String) {
        let shareContainer = app.otherElements["ShareSheet.RemoteContainerView"]
        XCTAssertTrue(shareContainer.waitForExistence(timeout: 5), "The result should open the system share sheet.")
        let preview = app.navigationBars[title]
        XCTAssertTrue(preview.waitForExistence(timeout: 3), "The share preview should identify the completed result and move count.")
        XCTAssertTrue(preview.images.firstMatch.exists, "The share preview should contain the rendered board thumbnail.")
        // Newer system share sheets expose activities as cells rather than buttons.
        // Copy is account-independent; merely inspect it without sharing or copying anything.
        XCTAssertTrue(app.cells["Copy"].exists || app.buttons["Copy"].exists, "The share sheet should expose the generated result image.")
    }
}
