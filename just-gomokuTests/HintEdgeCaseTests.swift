import Foundation
import XCTest
@testable import just_gomoku

@MainActor
final class HintEdgeCaseTests: XCTestCase {
    func testHintPublishesForUnchangedPosition() async throws {
        let fixture = makeGame(session: GameSession(configuration: .init(boardSize: 9)))
        defer { cleanUp(fixture) }

        fixture.game.askForHint()
        try await waitForHint(on: fixture.game)

        XCTAssertEqual(fixture.game.hint, Position(r: 4, c: 4))
        XCTAssertTrue(fixture.game.moves.isEmpty)
    }

    func testAcceptedMoveInvalidatesPendingHint() async throws {
        let fixture = makeGame(session: GameSession(configuration: .init(boardSize: 9)))
        defer { cleanUp(fixture) }

        // Both calls run on the main actor without yielding. The hint task must
        // therefore process its empty-board snapshot after the accepted move.
        fixture.game.askForHint()
        XCTAssertTrue(fixture.game.playHuman(at: Position(r: 0, c: 0)))
        try await allowPendingHintToFinish()

        XCTAssertEqual(fixture.game.current, .white)
        XCTAssertEqual(fixture.game.moves.count, 1)
        XCTAssertNil(fixture.game.hint, "A hint for Black's previous position must not appear on White's turn")
    }

    func testWinningMoveInvalidatesPendingHint() async throws {
        var session = GameSession(configuration: .init(boardSize: 5))
        for column in 0..<4 {
            XCTAssertTrue(session.place(at: Position(r: 0, c: column), controller: .human))
            XCTAssertTrue(session.place(at: Position(r: 1, c: column), controller: .human))
        }
        XCTAssertTrue(session.isValid)
        let fixture = makeGame(session: session)
        defer { cleanUp(fixture) }

        fixture.game.askForHint()
        XCTAssertTrue(fixture.game.playHuman(at: Position(r: 0, c: 4)))
        XCTAssertEqual(fixture.game.winner, .black)
        try await allowPendingHintToFinish()

        XCTAssertTrue(fixture.game.gameOver)
        XCTAssertEqual(fixture.game.moves.count, 9)
        XCTAssertNil(fixture.game.hint, "A completed game must not receive a pending hint")
    }

    func testNewRoundInvalidatesPendingHint() async throws {
        let fixture = makeGame(session: GameSession(configuration: .init(boardSize: 9)))
        defer { cleanUp(fixture) }
        let previousSessionID = fixture.game.session.id

        fixture.game.askForHint()
        fixture.game.newRound(configuration: .init(boardSize: 5))
        try await allowPendingHintToFinish()

        XCTAssertNotEqual(fixture.game.session.id, previousSessionID)
        XCTAssertEqual(fixture.game.boardSize, 5)
        XCTAssertTrue(fixture.game.moves.isEmpty)
        XCTAssertNil(fixture.game.hint)
    }

    func testUndoInvalidatesPendingHint() async throws {
        var session = GameSession(configuration: .init(boardSize: 9))
        XCTAssertTrue(session.place(at: Position(r: 4, c: 4), controller: .human))
        let fixture = makeGame(session: session)
        defer { cleanUp(fixture) }

        fixture.game.askForHint()
        XCTAssertTrue(fixture.game.undo())
        try await allowPendingHintToFinish()

        XCTAssertEqual(fixture.game.current, .black)
        XCTAssertTrue(fixture.game.moves.isEmpty)
        XCTAssertNil(fixture.game.hint)
    }

    func testBackgroundAndResumeClearVisibleHint() async throws {
        let fixture = makeGame(session: GameSession(configuration: .init(boardSize: 9)))
        defer { cleanUp(fixture) }

        fixture.game.askForHint()
        try await waitForHint(on: fixture.game)
        XCTAssertEqual(fixture.game.hint, Position(r: 4, c: 4))

        // Backgrounding cancels the expiry task before its three-second timer
        // fires, so the scene transition must also clear the visible hint.
        fixture.game.sceneBecameInactive()
        XCTAssertNil(fixture.game.hint, "Backgrounding must clear an already visible hint immediately")

        fixture.game.sceneBecameActive()
        XCTAssertNil(fixture.game.hint, "Resuming must not restore a transient hint with a cancelled expiry")
        try await allowPendingHintToFinish()
        XCTAssertNil(fixture.game.hint, "The cancelled hint task must not republish a hint after resuming")
    }

    private func makeGame(session: GameSession) -> (game: GameState, fileURL: URL) {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustGomokuHintTests-\(UUID().uuidString).json")
        let store = ActiveSessionStore(fileURL: fileURL)
        store.save(session)
        let game = GameState(sessionStore: store)
        XCTAssertEqual(game.session.id, session.id, "The fixture must restore the intended session")
        return (game, fileURL)
    }

    private func cleanUp(_ fixture: (game: GameState, fileURL: URL)) {
        fixture.game.clearHint()
        try? FileManager.default.removeItem(at: fixture.fileURL)
    }

    private func waitForHint(on game: GameState) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while game.hint == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(game.hint, "The actual hint engine should finish within the bounded wait")
    }

    private func allowPendingHintToFinish() async throws {
        // These 5×5 and 9×9 positions finish immediately or within the engine's
        // 300 ms budget. Keep a margin while staying below its 3-second expiry.
        try await Task.sleep(for: .milliseconds(700))
    }
}
