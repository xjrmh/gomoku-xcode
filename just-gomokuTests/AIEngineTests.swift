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

    func testAIAlwaysTakesImmediateWin() {
        var board = Array(repeating: CellState.empty, count: 9 * 9)
        for column in 2...5 { board[4 * 9 + column] = .white }

        for difficulty in AIDifficulty.allCases {
            let move = AIEngine.computeBestMove(for: .white, board: board, size: 9, difficulty: difficulty)
            XCTAssertTrue(move == .init(r: 4, c: 1) || move == .init(r: 4, c: 6))
        }
    }

    func testAIAlwaysBlocksImmediateLoss() {
        var board = Array(repeating: CellState.empty, count: 9 * 9)
        for row in 1...4 { board[row * 9 + 6] = .black }

        for difficulty in AIDifficulty.allCases {
            let move = AIEngine.computeBestMove(for: .white, board: board, size: 9, difficulty: difficulty)
            XCTAssertTrue(move == .init(r: 0, c: 6) || move == .init(r: 5, c: 6))
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
}
