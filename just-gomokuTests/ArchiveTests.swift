import SwiftData
import XCTest
@testable import just_gomoku

@MainActor
final class ArchiveTests: XCTestCase {
    func testArchivePreservesReplayAndMixedModes() throws {
        var session = GameSession(configuration: .init(mode: .pvp, boardSize: 9))
        XCTAssertTrue(session.place(at: .init(r: 4, c: 4), controller: .human))
        session.setMode(.ai)
        XCTAssertTrue(session.place(at: .init(r: 4, c: 5), controller: .human))
        session.outcome = .draw

        let archive = ArchivedGame(session: session)

        XCTAssertEqual(archive.moves, session.moves)
        XCTAssertEqual(archive.finalBoard, session.board)
        XCTAssertEqual(archive.modes, [.pvp, .ai])
        XCTAssertEqual(archive.resultTitle, "Draw")
    }

    func testRepositoryReplacesDuplicateAndReopensArchivedGame() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ArchivedGame.self, configurations: configuration)
        let context = container.mainContext
        var session = GameSession(configuration: .init(boardSize: 9))
        session.outcome = .draw

        ArchiveRepository.archive(session, in: context)
        ArchiveRepository.archive(session, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ArchivedGame>()).count, 1)

        ArchiveRepository.reopen(session.id, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ArchivedGame>()).isEmpty)
    }
}
