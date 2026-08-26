import Foundation
#if os(macOS)
import Security
#endif
import SwiftData

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

    init(session: GameSession, completedAt: Date = .now) {
        sessionID = session.id
        schemaVersion = session.schemaVersion
        self.completedAt = completedAt
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

        switch session.outcome {
        case .ongoing:
            outcomeRaw = "ongoing"
            winnerRaw = nil
        case .draw:
            outcomeRaw = "draw"
            winnerRaw = nil
        case let .win(player, _):
            outcomeRaw = "win"
            winnerRaw = player.rawValue
        }
    }

    var winner: Player? { winnerRaw.flatMap(Player.init(rawValue:)) }
    var resultTitle: String {
        if let winner { return "\(winner.name) won" }
        return outcomeRaw == "draw" ? "Draw" : "Unfinished"
    }
    var finalMode: GameMode { GameMode(rawValue: finalModeRaw) ?? .pvp }
    var difficulty: AIDifficulty { AIDifficulty(rawValue: difficultyRaw) ?? .medium }
    var humanSide: Player { Player(rawValue: humanSideRaw) ?? .white }
    var modes: Set<GameMode> {
        Set(modesRaw.split(separator: ",").compactMap { GameMode(rawValue: String($0)) })
    }
    var moves: [MoveRecord] {
        guard let movesData else { return [] }
        return (try? JSONDecoder().decode([MoveRecord].self, from: movesData)) ?? []
    }
    var winningLine: [Position] {
        guard let winningLineData else { return [] }
        return (try? JSONDecoder().decode([Position].self, from: winningLineData)) ?? []
    }
    var finalBoard: [CellState] { board(after: moves.count) }

    func board(after moveIndex: Int) -> [CellState] {
        var board = Array(repeating: CellState.empty, count: boardSize * boardSize)
        for move in moves.prefix(max(0, min(moveIndex, moves.count))) {
            let index = move.pos.r * boardSize + move.pos.c
            guard board.indices.contains(index) else { continue }
            board[index] = move.player.cellState
        }
        return board
    }
}

enum ArchiveContainer {
    static func make() -> ModelContainer {
        let schema = Schema([ArchivedGame.self])
        if let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            try? FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
        }
        if hasCloudKitEntitlement {
            do {
                let cloud = ModelConfiguration(
                    "CloudArchive",
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.com.xjrmh.gomoku")
                )
                return try ModelContainer(for: schema, configurations: cloud)
            } catch {
                // A signed build can still be offline or have iCloud disabled.
                // The archive remains usable locally and can reconnect on a later launch.
            }
        }

        do {
            let local = ModelConfiguration("LocalArchive", schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            do {
                let memory = ModelConfiguration("MemoryArchive", schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: memory)
            } catch {
                preconditionFailure("Unable to create the Gomoku archive store: \(error)")
            }
        }
    }

    private static var hasCloudKitEntitlement: Bool {
        #if targetEnvironment(simulator)
        return false
        #elseif os(iOS)
        // A physical iOS build cannot install without satisfying the app's
        // signed iCloud entitlements, so it is safe to configure CloudKit.
        return true
        #else
        guard let task = SecTaskCreateFromSelf(nil),
              let containers = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) as? [String] else { return false }
        return containers.contains("iCloud.com.xjrmh.gomoku")
        #endif
    }
}

@MainActor
enum ArchiveRepository {
    static func archive(_ session: GameSession, in context: ModelContext) {
        let id = session.id
        var descriptor = FetchDescriptor<ArchivedGame>(predicate: #Predicate { $0.sessionID == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        }
        context.insert(ArchivedGame(session: session))
        try? context.save()
    }

    static func reopen(_ sessionID: UUID, in context: ModelContext) {
        var descriptor = FetchDescriptor<ArchivedGame>(predicate: #Predicate { $0.sessionID == sessionID })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            try? context.save()
        }
    }

    static func eraseAll(in context: ModelContext) {
        try? context.delete(model: ArchivedGame.self)
        try? context.save()
    }
}
