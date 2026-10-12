import XCTest
@testable import just_gomoku

final class AIEngineTests: XCTestCase {
    func testEmptyBoardStartsAtCenterForEveryDifficulty() {
        let board = Array(repeating: CellState.empty, count: 9 * 9)
        for difficulty in AIDifficulty.allCases {
            XCTAssertEqual(
                AIEngine.computeBestMove(for: .black, board: board, size: 9, difficulty: difficulty),
                Position(r: 4, c: 4)
            )
        }
    }

    func testAIAlwaysTakesImmediateWinBeforeBlockingOpponent() throws {
        let session = try legalSession(
            size: 9,
            history: ["C5", "C4", "D5", "D4", "E5", "E4", "F5", "F4"]
        )
        let wins = winningMoves(board: session.board, size: 9, player: .black)
        XCTAssertEqual(wins, [position("B5"), position("G5")])
        XCTAssertFalse(winningMoves(board: session.board, size: 9, player: .white).isEmpty)

        for difficulty in AIDifficulty.allCases {
            let move = try XCTUnwrap(AIEngine.computeBestMove(
                for: .black, board: session.board, size: 9, difficulty: difficulty
            ))
            XCTAssertTrue(wins.contains(move), "\(difficulty) must take its own win")
        }
    }

    func testAIAlwaysBlocksTheOnlyImmediateWinningPoint() throws {
        // G1 closes one end of Black's four. An open four cannot be saved
        // by blocking either end, so the old two-endpoint fixture was unwinnable.
        let session = try legalSession(
            size: 9,
            history: ["G2", "G1", "G3", "A1", "G4", "C1", "G5"]
        )
        XCTAssertEqual(session.current, .white)
        XCTAssertEqual(winningMoves(board: session.board, size: 9, player: .black), [position("G6")])
        XCTAssertTrue(winningMoves(board: session.board, size: 9, player: .white).isEmpty)

        for difficulty in AIDifficulty.allCases {
            XCTAssertEqual(
                AIEngine.computeBestMove(for: .white, board: session.board, size: 9, difficulty: difficulty),
                position("G6"),
                "\(difficulty) must block the unique immediate win"
            )
        }
    }

    func testHardBlocksForcedDoubleFourAtProductionDeadlineInEveryBoardSymmetry() throws {
        for symmetry in 0..<8 {
            // Shift the fixture away from center before transforming it so
            // the required move changes coordinates across the symmetries.
            let history = forcedDefenseHistory.map {
                let original = position($0)
                return transform(Position(r: original.r - 1, c: original.c - 1), size: 15, symmetry: symmetry)
            }
            let session = try legalSession(size: 15, positions: history)
            let expected = transform(position("G7"), size: 15, symmetry: symmetry)
            XCTAssertEqual(session.current, .black)
            XCTAssertTrue(winningMoves(board: session.board, size: 15, player: .black).isEmpty)
            XCTAssertTrue(winningMoves(board: session.board, size: 15, player: .white).isEmpty)

            let move = AIEngine.computeBestMove(
                for: .black,
                board: session.board,
                size: 15,
                difficulty: .hard,
                deadline: .now.advanced(by: .milliseconds(750))
            )
            XCTAssertEqual(move, expected, "Only this move prevents a forced White fork; symmetry \(symmetry)")
        }
    }

    func testForcedDefenseFixtureHasTwoIndependentWinsAndNoCounterwin() throws {
        let session = try legalSession(size: 15, history: forcedDefenseHistory)
        var board = placing(.black, at: position("E8"), on: session.board, size: 15)
        board = placing(.white, at: position("H8"), on: board, size: 15)
        XCTAssertTrue(winningMoves(board: board, size: 15, player: .black).isEmpty)
        XCTAssertEqual(winningMoves(board: board, size: 15, player: .white), [position("J8"), position("H10")])

        // Black has no immediate win and a single stone cannot stop both
        // J8 and H10. Check every legal reply, including distant squares.
        for reply in emptyPositions(board: board, size: 15) {
            let defended = placing(.black, at: reply, on: board, size: 15)
            XCTAssertFalse(
                winningMoves(board: defended, size: 15, player: .white).isEmpty,
                "White's fork must survive Black \(reply.coordinate)"
            )
        }
    }

    func testHardCreatesItsOwnForcedDoubleFour() throws {
        let session = try legalSession(
            size: 15,
            history: ["F8", "E8", "G8", "H5", "I8", "A1", "H6", "C2", "H7", "J3", "H9", "K1"]
        )
        XCTAssertTrue(winningMoves(board: session.board, size: 15, player: .black).isEmpty)
        XCTAssertTrue(winningMoves(board: session.board, size: 15, player: .white).isEmpty)
        let move = try XCTUnwrap(AIEngine.computeBestMove(
            for: .black,
            board: session.board,
            size: 15,
            difficulty: .hard,
            deadline: .now.advanced(by: .milliseconds(750))
        ))
        XCTAssertEqual(move, position("H8"))
        let fork = placing(.black, at: move, on: session.board, size: 15)
        XCTAssertEqual(winningMoves(board: fork, size: 15, player: .black), [position("J8"), position("H10")])
        XCTAssertTrue(winningMoves(board: fork, size: 15, player: .white).isEmpty)
    }

    func testExpiredHardSearchRetainsSafeForcedDefense() throws {
        let session = try legalSession(size: 15, history: forcedDefenseHistory)
        let result = AIEngine.analyzeMove(
            for: .black,
            board: session.board,
            size: 15,
            difficulty: .hard,
            deadline: .now.advanced(by: .seconds(-1))
        )
        XCTAssertEqual(result.position, position("H8"))
        XCTAssertEqual(result.completedDepth, 0)
    }

    func testCancelledHardMoveRetainsSafeForcedDefense() async throws {
        let session = try legalSession(size: 15, history: forcedDefenseHistory)
        let board = session.board
        let task = Task.detached {
            // Cancellation wakes the suspension before entering the engine,
            // guaranteeing that the search starts in a cancelled task.
            try? await Task.sleep(for: .seconds(1))
            return AIEngine.computeBestMove(
                for: .black,
                board: board,
                size: 15,
                difficulty: .hard,
                deadline: .now.advanced(by: .milliseconds(750))
            )
        }
        task.cancel()
        let move = await task.value
        XCTAssertEqual(move, position("H8"))
    }

    func testExpiredHardSearchStillReturnsAnEmptyInBoundsMove() throws {
        let session = try legalSession(size: 9, history: ["E5", "D4", "F6", "D6"])
        let move = try XCTUnwrap(AIEngine.computeBestMove(
            for: session.current,
            board: session.board,
            size: 9,
            difficulty: .hard,
            deadline: .now.advanced(by: .seconds(-1))
        ))
        XCTAssertTrue(session.contains(move))
        XCTAssertEqual(session.state(at: move), .empty)
    }

    func testHardActuallySearchesAndCachePreservesCompletedResult() throws {
        let session = try legalSession(
            size: 7,
            history: ["A3", "E1", "G3", "F1", "A5", "B2", "E6", "C6", "D7", "F6"]
        )
        let cached = AIEngine.analyzeMove(
            for: .black,
            board: session.board,
            size: 7,
            difficulty: .hard,
            deadline: .now.advanced(by: .seconds(30)),
            searchOptions: .init(maxDepth: 4, useTranspositionTable: true)
        )
        let uncached = AIEngine.analyzeMove(
            for: .black,
            board: session.board,
            size: 7,
            difficulty: .hard,
            deadline: .now.advanced(by: .seconds(30)),
            searchOptions: .init(maxDepth: 4, useTranspositionTable: false)
        )
        XCTAssertEqual(cached.completedDepth, 4)
        XCTAssertEqual(uncached.completedDepth, 4)
        XCTAssertGreaterThan(cached.visitedNodes, 0)
        XCTAssertGreaterThan(uncached.visitedNodes, 0)
        XCTAssertFalse(cached.interrupted)
        XCTAssertFalse(uncached.interrupted)
        XCTAssertEqual(cached.position, uncached.position, "Caching must not change a completed search")
        XCTAssertEqual(cached.score, uncached.score, "Cached bounds must preserve the completed score")
        let move = try XCTUnwrap(cached.position)
        XCTAssertTrue(session.contains(move))
        XCTAssertEqual(session.state(at: move), .empty)
    }

    func testInterruptedHardSearchKeepsTheLastCompletedIteration() throws {
        let session = try legalSession(
            size: 7,
            history: ["A3", "E1", "G3", "F1", "A5", "B2", "E6", "C6", "D7", "F6"]
        )
        let interrupted = AIEngine.analyzeMove(
            for: .black,
            board: session.board,
            size: 7,
            difficulty: .hard,
            deadline: .now.advanced(by: .milliseconds(20)),
            searchOptions: .init(maxDepth: 12, useTranspositionTable: true)
        )
        XCTAssertTrue(interrupted.interrupted)
        XCTAssertLessThan(interrupted.completedDepth, 12)
        XCTAssertGreaterThan(interrupted.visitedNodes, 0)
        let move = try XCTUnwrap(interrupted.position)
        XCTAssertTrue(session.contains(move))
        XCTAssertEqual(session.state(at: move), .empty)

        if interrupted.completedDepth == 0 {
            XCTAssertNil(interrupted.score, "An unfinished first iteration must retain the unscored fallback")
        } else {
            let completed = AIEngine.analyzeMove(
                for: .black,
                board: session.board,
                size: 7,
                difficulty: .hard,
                deadline: .now.advanced(by: .seconds(30)),
                searchOptions: .init(maxDepth: interrupted.completedDepth, useTranspositionTable: true)
            )
            XCTAssertEqual(completed.completedDepth, interrupted.completedDepth)
            XCTAssertFalse(completed.interrupted)
            XCTAssertTrue(try XCTUnwrap(interrupted.score).isFinite)
            XCTAssertTrue(try XCTUnwrap(completed.score).isFinite)
            XCTAssertEqual(interrupted.position, completed.position, "A partial iteration must not replace the completed move")
            XCTAssertEqual(interrupted.score, completed.score, "A partial iteration must not replace the completed score")
        }
    }

    func testEasyMoveIsDeterministicForSeed() {
        var board = Array(repeating: CellState.empty, count: 9 * 9)
        board[4 * 9 + 4] = .black

        let first = AIEngine.computeBestMove(for: .white, board: board, size: 9, difficulty: .easy, seed: 42)
        let second = AIEngine.computeBestMove(for: .white, board: board, size: 9, difficulty: .easy, seed: 42)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map { board[$0.r * 9 + $0.c] }, .empty)
    }

    private var forcedDefenseHistory: [String] {
        ["E4", "F8", "H5", "G8", "F9", "I8", "K4", "H6", "D7", "H7", "D12", "H9", "F11", "I11", "J5", "J6", "E5", "L5"]
    }

    private func legalSession(size: Int, history: [String], file: StaticString = #filePath, line: UInt = #line) throws -> GameSession {
        try legalSession(size: size, positions: history.map(position), file: file, line: line)
    }

    private func legalSession(size: Int, positions: [Position], file: StaticString = #filePath, line: UInt = #line) throws -> GameSession {
        var configuration = GameConfiguration()
        configuration.boardSize = size
        var session = GameSession(configuration: configuration)
        for move in positions {
            XCTAssertTrue(session.place(at: move, controller: .human), "Illegal fixture move \(move.coordinate)", file: file, line: line)
            XCTAssertEqual(session.outcome, .ongoing, "Fixture must not end before the AI turn", file: file, line: line)
        }
        XCTAssertTrue(session.isValid, file: file, line: line)
        return session
    }

    private func position(_ coordinate: String) -> Position {
        Position(r: Int(coordinate.dropFirst())! - 1, c: Int(coordinate.utf8.first!) - 65)
    }

    private func transform(_ position: Position, size: Int, symmetry: Int) -> Position {
        var result = symmetry >= 4 ? Position(r: position.r, c: size - 1 - position.c) : position
        for _ in 0..<(symmetry % 4) {
            result = Position(r: result.c, c: size - 1 - result.r)
        }
        return result
    }

    private func emptyPositions(board: [CellState], size: Int) -> [Position] {
        board.indices.compactMap { board[$0] == .empty ? Position(r: $0 / size, c: $0 % size) : nil }
    }

    private func placing(_ player: Player, at position: Position, on board: [CellState], size: Int) -> [CellState] {
        var result = board
        result[position.r * size + position.c] = player.cellState
        return result
    }

    private func winningMoves(board: [CellState], size: Int, player: Player) -> [Position] {
        emptyPositions(board: board, size: size).filter { position in
            [(1, 0), (0, 1), (1, 1), (1, -1)].contains { dr, dc in
                var count = 1
                for sign in [-1, 1] {
                    var row = position.r + dr * sign
                    var column = position.c + dc * sign
                    while (0..<size).contains(row), (0..<size).contains(column), board[row * size + column] == player.cellState {
                        count += 1
                        row += dr * sign
                        column += dc * sign
                    }
                }
                return count >= 5
            }
        }
    }
}
