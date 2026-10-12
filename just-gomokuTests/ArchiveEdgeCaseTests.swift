import SwiftData
import XCTest
@testable import just_gomoku

@MainActor
final class ArchiveEdgeCaseTests: XCTestCase {
    func testPlayedFullBoardDrawIsValidAndEveryReplayPrefixMatches() throws {
        let session = playedDraw()
        XCTAssertEqual(session.outcome, .draw)
        XCTAssertEqual(session.moves.count, 25)
        XCTAssertTrue(session.isValid)
        XCTAssertNil(session.turnStartedAt)

        let restored = try JSONDecoder().decode(GameSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored, session)
        XCTAssertTrue(restored.isValid)

        let archive = ArchivedGame(session: restored)
        XCTAssertEqual(archive.resultTitle, "Draw")
        XCTAssertNil(archive.winner)
        XCTAssertTrue(archive.winningLine.isEmpty)
        XCTAssertEqual(archive.moves, session.moves)
        XCTAssertEqual(archive.finalBoard, session.board)

        var expected = Array(repeating: CellState.empty, count: 25)
        XCTAssertEqual(archive.board(after: -1), expected)
        XCTAssertEqual(archive.board(after: 0), expected)
        for (index, move) in session.moves.enumerated() {
            expected[move.pos.r * 5 + move.pos.c] = move.player.cellState
            XCTAssertEqual(archive.board(after: index + 1), expected, "Replay prefix \(index + 1)")
        }
        XCTAssertEqual(archive.board(after: 26), session.board)
        XCTAssertEqual(archive.board(after: Int.max), session.board)
    }

    func testTerminalDrawRejectsFurtherMovesAndUndoReopensExactlyOneCell() {
        var session = playedDraw()
        session.archived = true
        let completed = session

        XCTAssertFalse(session.place(at: .init(r: 4, c: 4), controller: .human, now: date(100)))
        XCTAssertFalse(session.place(at: .init(r: 5, c: 5), controller: .human, now: date(100)))
        XCTAssertEqual(session, completed)

        let undone = session.undoOne(now: date(100))
        XCTAssertEqual(undone?.pos, Position(r: 4, c: 4))
        XCTAssertEqual(undone?.player, .black)
        XCTAssertEqual(session.outcome, .ongoing)
        XCTAssertEqual(session.current, .black)
        XCTAssertEqual(session.moves.count, 24)
        XCTAssertEqual(session.board.filter { $0 == .empty }.count, 1)
        XCTAssertFalse(session.archived)
        XCTAssertTrue(session.isValid)

        XCTAssertTrue(session.place(at: .init(r: 4, c: 4), controller: .human, now: date(101)))
        XCTAssertEqual(session.outcome, .draw)
        XCTAssertTrue(session.isValid)
        XCTAssertEqual(session.board, completed.board)
    }

    func testLargeArchiveKeepsDistinctSessionsAndSupportsReplaceReopenAndErase() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: ArchivedGame.self, configurations: configuration)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let sizes = [5, 9, 15, 19, 25]
        let count = 250
        var sessions: [GameSession] = []
        for index in 0..<count {
            let session = index.isMultiple(of: 5) ? playedDraw() : playedWin(boardSize: sizes[index % sizes.count])
            XCTAssertTrue(session.isValid)
            sessions.append(session)
            context.insert(ArchivedGame(session: session, completedAt: date(TimeInterval(index))))
        }
        try context.save()

        let descriptor = FetchDescriptor<ArchivedGame>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        let stored = try context.fetch(descriptor)
        XCTAssertEqual(stored.count, count)
        XCTAssertEqual(Set(stored.map(\.sessionID)).count, count)
        XCTAssertEqual(stored.first?.sessionID, sessions.last?.id)
        XCTAssertEqual(stored.last?.sessionID, sessions.first?.id)
        XCTAssertTrue(stored.contains { $0.resultTitle == "Draw" && $0.moveCount == 25 })
        XCTAssertTrue(stored.contains { $0.boardSize == 25 && $0.resultTitle == "Black won" })

        let replacement = sessions[count / 2]
        ArchiveRepository.archive(replacement, in: context)
        let afterReplacement = try context.fetch(descriptor)
        XCTAssertEqual(afterReplacement.count, count)
        XCTAssertEqual(afterReplacement.filter { $0.sessionID == replacement.id }.count, 1)
        XCTAssertEqual(afterReplacement.first?.sessionID, replacement.id)
        XCTAssertEqual(afterReplacement.first?.finalBoard, replacement.board)

        ArchiveRepository.reopen(replacement.id, in: context)
        let afterReopen = try context.fetch(descriptor)
        XCTAssertEqual(afterReopen.count, count - 1)
        XCTAssertFalse(afterReopen.contains { $0.sessionID == replacement.id })

        ArchiveRepository.eraseAll(in: context)
        XCTAssertTrue(try context.fetch(descriptor).isEmpty)
    }

    func testDiskArchiveSurvivesFreshContainersAndReopenDeletionIsDurable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustGomokuArchivePersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("archive.store")
        let win = playedWin(boardSize: 9)
        let draw = playedDraw()
        XCTAssertTrue(win.isValid)
        XCTAssertTrue(draw.isValid)

        try withDiskArchive(at: storeURL) { context in
            ArchiveRepository.archive(win, in: context)
            ArchiveRepository.archive(draw, in: context)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ArchivedGame>()), 2)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        // Each helper invocation releases its models, context, and container
        // before the next one opens the same store. No model objects escape.
        try withDiskArchive(at: storeURL) { context in
            let games = try context.fetch(FetchDescriptor<ArchivedGame>())
            XCTAssertEqual(games.count, 2)
            let storedWin = try XCTUnwrap(games.first { $0.sessionID == win.id })
            let storedDraw = try XCTUnwrap(games.first { $0.sessionID == draw.id })
            assertPersistedReplay(storedWin, matches: win, result: "Black won")
            assertPersistedReplay(storedDraw, matches: draw, result: "Draw")
        }

        try withDiskArchive(at: storeURL) { context in
            ArchiveRepository.reopen(win.id, in: context)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ArchivedGame>()), 1)
        }

        try withDiskArchive(at: storeURL) { context in
            let games = try context.fetch(FetchDescriptor<ArchivedGame>())
            XCTAssertEqual(games.count, 1)
            XCTAssertFalse(games.contains { $0.sessionID == win.id })
            let storedDraw = try XCTUnwrap(games.first)
            XCTAssertEqual(storedDraw.sessionID, draw.id)
            assertPersistedReplay(storedDraw, matches: draw, result: "Draw")
            ArchiveRepository.eraseAll(in: context)
        }

        try withDiskArchive(at: storeURL) { context in
            XCTAssertTrue(try context.fetch(FetchDescriptor<ArchivedGame>()).isEmpty)
        }
    }

    private func withDiskArchive(at url: URL, body: (ModelContext) throws -> Void) throws {
        try autoreleasepool {
            let schema = Schema([ArchivedGame.self])
            let configuration = ModelConfiguration(
                "ArchivePersistence", schema: schema, url: url, cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: configuration)
            defer { withExtendedLifetime(container) {} }
            let context = container.mainContext
            // Exercise the repository's explicit saves rather than autosave.
            context.autosaveEnabled = false
            try body(context)
        }
    }

    private func assertPersistedReplay(_ archive: ArchivedGame, matches session: GameSession, result: String) {
        XCTAssertEqual(archive.sessionID, session.id)
        XCTAssertEqual(archive.resultTitle, result)
        XCTAssertEqual(archive.boardSize, session.boardSize)
        XCTAssertEqual(archive.moveCount, session.moves.count)
        XCTAssertEqual(archive.moves, session.moves)
        XCTAssertEqual(archive.winner, session.outcome.winner)
        XCTAssertEqual(archive.winningLine, session.outcome.winningLine)
        XCTAssertEqual(archive.blackElapsed, session.clocks.black)
        XCTAssertEqual(archive.whiteElapsed, session.clocks.white)
        XCTAssertEqual(archive.finalBoard, session.board)

        var board = Array(repeating: CellState.empty, count: session.boardSize * session.boardSize)
        XCTAssertEqual(archive.board(after: 0), board)
        for (index, move) in session.moves.enumerated() {
            board[move.pos.r * session.boardSize + move.pos.c] = move.player.cellState
            XCTAssertEqual(archive.board(after: index + 1), board, "Persisted replay prefix \(index + 1)")
        }
    }

    private func playedDraw() -> GameSession {
        let rows = [
            [1, 1, 2, 2, 1],
            [2, 2, 1, 1, 2],
            [1, 1, 2, 2, 1],
            [2, 2, 1, 1, 2],
            [1, 2, 1, 2, 1],
        ]
        var positions: [Player: [Position]] = [.black: [], .white: []]
        for row in rows.indices {
            for column in rows[row].indices {
                positions[Player(rawValue: rows[row][column])!, default: []].append(.init(r: row, c: column))
            }
        }
        var session = GameSession(configuration: .init(boardSize: 5))
        for index in 0..<13 {
            XCTAssertTrue(session.place(at: positions[.black]![index], controller: .human, now: date(TimeInterval(index * 2))))
            if index < 12 {
                XCTAssertTrue(session.place(at: positions[.white]![index], controller: .human, now: date(TimeInterval(index * 2 + 1))))
            }
        }
        return session
    }

    private func playedWin(boardSize: Int) -> GameSession {
        var session = GameSession(configuration: .init(boardSize: boardSize))
        for column in 0..<5 {
            XCTAssertTrue(session.place(at: .init(r: 0, c: column), controller: .human, now: date(TimeInterval(column * 2))))
            if column < 4 {
                XCTAssertTrue(session.place(at: .init(r: 1, c: column), controller: .human, now: date(TimeInterval(column * 2 + 1))))
            }
        }
        return session
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }
}
