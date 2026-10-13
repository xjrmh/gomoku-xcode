import SwiftData
import XCTest
@testable import just_gomoku

@MainActor
final class ArchiveThemeTests: XCTestCase {
    func testArchiveDefaultsToStandardAndUnknownThemeKeepsReplay() {
        let session = finishedGame()
        let archive = ArchivedGame(session: session)

        XCTAssertEqual(archive.theme, .standard)
        XCTAssertEqual(archive.resultTitle, "Black won")

        archive.themeRaw = "future-holiday"

        XCTAssertEqual(archive.theme, .standard)
        XCTAssertEqual(archive.resultTitle, "Black won")
        XCTAssertEqual(archive.moves, session.moves)
        XCTAssertEqual(archive.finalBoard, session.board)
    }

    func testEachArchivedGameKeepsItsSelectedThemeWhenPreferencesChange() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: ArchivedGame.self, configurations: configuration)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let suite = "JustGomokuArchiveThemeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults, cloud: nil)
        let standard = finishedGame()
        let halloween = finishedGame()

        ArchiveRepository.archive(standard, theme: preferences.theme, in: context)
        preferences.theme = .halloween
        ArchiveRepository.archive(halloween, theme: preferences.theme, in: context)
        preferences.theme = .ocean

        let games = try context.fetch(FetchDescriptor<ArchivedGame>())
        XCTAssertEqual(games.count, 2)
        let storedStandard = try XCTUnwrap(games.first { $0.sessionID == standard.id })
        let storedHalloween = try XCTUnwrap(games.first { $0.sessionID == halloween.id })
        XCTAssertEqual(storedStandard.theme, .standard)
        XCTAssertEqual(storedStandard.resultTitle, "Black won")
        XCTAssertEqual(storedHalloween.theme, .halloween)
        XCTAssertEqual(storedHalloween.resultTitle, "Pumpkin won")
        XCTAssertEqual(storedStandard.finalBoard, standard.board)
        XCTAssertEqual(storedHalloween.finalBoard, halloween.board)

        // Undoing and finishing again replaces the archive with the new result's theme.
        ArchiveRepository.reopen(halloween.id, in: context)
        ArchiveRepository.archive(halloween, theme: preferences.theme, in: context)
        let updated = try context.fetch(FetchDescriptor<ArchivedGame>())
        XCTAssertEqual(updated.count, 2)
        let replacement = try XCTUnwrap(updated.first { $0.sessionID == halloween.id })
        XCTAssertEqual(replacement.theme, .ocean)
        XCTAssertEqual(replacement.resultTitle, "Shell won")
        XCTAssertEqual(updated.first { $0.sessionID == standard.id }?.theme, .standard)
    }

    func testArchivedThemesSurviveFreshDiskContainers() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("archive.store")
        let standard = finishedGame()
        let halloween = finishedGame()

        try withStore(schema: Schema([ArchivedGame.self]), at: storeURL) { context in
            ArchiveRepository.archive(standard, in: context)
            ArchiveRepository.archive(halloween, theme: .halloween, in: context)
        }

        try withStore(schema: Schema([ArchivedGame.self]), at: storeURL) { context in
            let games = try context.fetch(FetchDescriptor<ArchivedGame>())
            XCTAssertEqual(games.count, 2)
            let storedStandard = try XCTUnwrap(games.first { $0.sessionID == standard.id })
            let storedHalloween = try XCTUnwrap(games.first { $0.sessionID == halloween.id })
            XCTAssertEqual(storedStandard.theme, .standard)
            XCTAssertEqual(storedStandard.resultTitle, "Black won")
            XCTAssertEqual(storedHalloween.theme, .halloween)
            XCTAssertEqual(storedHalloween.resultTitle, "Pumpkin won")
            XCTAssertEqual(storedHalloween.moves, halloween.moves)
            XCTAssertEqual(storedHalloween.finalBoard, halloween.board)
        }
    }

    func testLegacyDiskArchiveMigratesToStandardWithoutLosingGames() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("archive.store")
        let session = finishedGame()
        let completedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

        // Create an actual pre-theme SwiftData store, then release the old container
        // before reopening it with the application's current schema.
        try withStore(schema: Schema([LegacyArchiveSchema.ArchivedGame.self]), at: storeURL) { context in
            context.insert(LegacyArchiveSchema.ArchivedGame(session: session, completedAt: completedAt))
            try context.save()
        }

        try withStore(schema: Schema([ArchivedGame.self]), at: storeURL) { context in
            let games = try context.fetch(FetchDescriptor<ArchivedGame>())
            XCTAssertEqual(games.count, 1)
            let migrated = try XCTUnwrap(games.first)
            XCTAssertEqual(migrated.sessionID, session.id)
            XCTAssertEqual(migrated.completedAt, completedAt)
            XCTAssertEqual(migrated.theme, .standard)
            XCTAssertEqual(migrated.resultTitle, "Black won")
            XCTAssertEqual(migrated.moves, session.moves)
            XCTAssertEqual(migrated.winningLine, session.outcome.winningLine)
            XCTAssertEqual(migrated.blackElapsed, session.clocks.black)
            XCTAssertEqual(migrated.whiteElapsed, session.clocks.white)
            XCTAssertEqual(migrated.finalBoard, session.board)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustGomokuArchiveThemes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func withStore(schema: Schema, at url: URL, body: (ModelContext) throws -> Void) throws {
        try autoreleasepool {
            let configuration = ModelConfiguration(
                "ArchiveThemes", schema: schema, url: url, cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: configuration)
            defer { withExtendedLifetime(container) {} }
            let context = container.mainContext
            context.autosaveEnabled = false
            try body(context)
        }
    }

    private func finishedGame() -> GameSession {
        var session = GameSession(configuration: .init(mode: .pvp, boardSize: 9))
        for column in 0..<5 {
            XCTAssertTrue(session.place(
                at: .init(r: 0, c: column), controller: .human,
                now: Date(timeIntervalSinceReferenceDate: Double(column * 2))
            ))
            if column < 4 {
                XCTAssertTrue(session.place(
                    at: .init(r: 1, c: column), controller: .human,
                    now: Date(timeIntervalSinceReferenceDate: Double(column * 2 + 1))
                ))
            }
        }
        XCTAssertTrue(session.isValid)
        return session
    }
}

/// Reproduces the stored model before per-game theme metadata was introduced.
/// The model's name and every pre-existing stored property match that schema.
private enum LegacyArchiveSchema {
    @Model
    final class ArchivedGame {
        var sessionID: UUID = UUID()
        var schemaVersion: Int = 1
        var completedAt: Date = Date()
        var outcomeRaw: String = "draw"
        var winnerRaw: Int?
        var boardSize: Int = 15
        var modesRaw: String = GameMode.pvp.rawValue
        var finalModeRaw: String = GameMode.pvp.rawValue
        var difficultyRaw: String = AIDifficulty.medium.rawValue
        var humanSideRaw: Int = Player.white.rawValue
        var moveCount: Int = 0
        var blackElapsed: TimeInterval = 0
        var whiteElapsed: TimeInterval = 0
        var movesData: Data?
        var winningLineData: Data?

        init(session: GameSession, completedAt: Date) {
            sessionID = session.id
            schemaVersion = session.schemaVersion
            self.completedAt = completedAt
            outcomeRaw = "win"
            winnerRaw = session.outcome.winner?.rawValue
            boardSize = session.boardSize
            let modes = Set(session.moves.map(\.mode)).union([session.configuration.mode])
            modesRaw = modes.map(\.rawValue).sorted().joined(separator: ",")
            finalModeRaw = session.configuration.mode.rawValue
            difficultyRaw = session.configuration.difficulty.rawValue
            humanSideRaw = session.configuration.humanSide.rawValue
            moveCount = session.moves.count
            blackElapsed = session.clocks.black
            whiteElapsed = session.clocks.white
            movesData = try? JSONEncoder().encode(session.moves)
            winningLineData = try? JSONEncoder().encode(session.outcome.winningLine)
        }
    }
}
