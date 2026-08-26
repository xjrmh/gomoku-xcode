import XCTest
@testable import just_gomoku

final class GameSessionTests: XCTestCase {
    func testAIControlsBlackByDefault() {
        let session = GameSession(configuration: .init(mode: .ai))
        XCTAssertEqual(session.configuration.humanSide, .white)
        XCTAssertEqual(session.aiPlayer, .black)
        XCTAssertTrue(session.isAITurn)
    }

    func testConfigurationNormalizesToSupportedOddSizes() {
        XCTAssertEqual(GameSession(configuration: .init(boardSize: 4)).boardSize, 5)
        XCTAssertEqual(GameSession(configuration: .init(boardSize: 10)).boardSize, 11)
        XCTAssertEqual(GameSession(configuration: .init(boardSize: 26)).boardSize, 25)
    }

    func testFreestyleOverlineWinsAndReturnsWholeLine() {
        var session = GameSession(configuration: .init(boardSize: 9))
        for column in [0, 1, 2, 4, 5] {
            session.board[4 * session.boardSize + column] = .black
        }

        XCTAssertTrue(session.place(at: .init(r: 4, c: 3), controller: .human, now: date(10)))
        XCTAssertEqual(session.outcome.winner, .black)
        XCTAssertEqual(session.outcome.winningLine, (0...5).map { Position(r: 4, c: $0) })
    }

    func testFullBoardWithoutFiveEndsInDraw() {
        var session = GameSession(configuration: .init(boardSize: 5))
        let rows = [
            [1, 1, 2, 2, 1],
            [2, 2, 1, 1, 2],
            [1, 1, 2, 2, 1],
            [2, 2, 1, 1, 2],
            [1, 2, 1, 2, 0],
        ]
        session.board = rows.flatMap { $0 }.map { CellState(rawValue: $0)! }

        XCTAssertTrue(session.place(at: .init(r: 4, c: 4), controller: .human, now: date(1)))
        XCTAssertEqual(session.outcome, .draw)
    }

    func testUndoRestoresExactClockSnapshotAndRestartsCurrentTurn() {
        var session = GameSession(configuration: .init(boardSize: 9))
        XCTAssertTrue(session.place(at: .init(r: 4, c: 4), controller: .human, now: date(0)))
        XCTAssertTrue(session.place(at: .init(r: 4, c: 5), controller: .human, now: date(4)))
        XCTAssertTrue(session.place(at: .init(r: 5, c: 5), controller: .human, now: date(10)))

        let undone = session.undoOne(now: date(20))

        XCTAssertEqual(undone?.player, .black)
        XCTAssertEqual(session.current, .black)
        XCTAssertEqual(session.clocks.black, 6, accuracy: 0.001)
        XCTAssertEqual(session.clocks.white, 4, accuracy: 0.001)
        XCTAssertEqual(session.elapsed(for: .black, now: date(23)), 9, accuracy: 0.001)
        XCTAssertEqual(session.elapsed(for: .white, now: date(23)), 4, accuracy: 0.001)
    }

    func testBackgroundTimeIsNotCounted() {
        var session = GameSession(configuration: .init(boardSize: 9))
        XCTAssertTrue(session.place(at: .init(r: 4, c: 4), controller: .human, now: date(0)))
        session.pause(now: date(3))
        XCTAssertEqual(session.clocks.white, 3, accuracy: 0.001)

        session.resume(now: date(100))

        XCTAssertEqual(session.elapsed(for: .white, now: date(105)), 8, accuracy: 0.001)
    }

    func testSwitchingModePreservesBoardAndRecordsTransition() {
        var session = GameSession(configuration: .init(mode: .pvp, boardSize: 9))
        XCTAssertTrue(session.place(at: .init(r: 4, c: 4), controller: .human, now: date(0)))
        let board = session.board

        session.setMode(.ai)

        XCTAssertEqual(session.board, board)
        XCTAssertEqual(session.moves.count, 1)
        XCTAssertEqual(session.configuration.mode, .ai)
        XCTAssertEqual(session.modeTransitions, [.init(moveIndex: 1, from: .pvp, to: .ai)])
    }

    func testSessionCodableRoundTripAndValidation() throws {
        var original = GameSession(configuration: .init(mode: .ai, boardSize: 15, difficulty: .hard, humanSide: .white))
        XCTAssertTrue(original.place(at: .init(r: 7, c: 7), controller: .ai, now: date(0)))

        let decoded = try JSONDecoder().decode(GameSession.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isValid)
    }

    func testValidationRejectsInconsistentPersistedBoard() {
        var session = GameSession(configuration: .init(boardSize: 9))
        XCTAssertTrue(session.place(at: .init(r: 4, c: 4), controller: .human, now: date(0)))
        session.board[4 * 9 + 4] = .white
        XCTAssertFalse(session.isValid)
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }
}
