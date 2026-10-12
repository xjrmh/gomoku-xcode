import Foundation

enum GameMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case pvp
    case ai

    var id: Self { self }
    var title: String { self == .pvp ? "2 Players" : "AI" }
}

enum AIDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy
    case medium
    case hard

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum CellState: Int, Codable, Sendable {
    case empty = 0
    case black = 1
    case white = 2

    var player: Player? {
        switch self {
        case .empty: nil
        case .black: .black
        case .white: .white
        }
    }
}

enum Player: Int, Codable, CaseIterable, Identifiable, Sendable {
    case black = 1
    case white = 2

    var id: Self { self }
    var next: Player { self == .black ? .white : .black }
    var cellState: CellState { self == .black ? .black : .white }
    var name: String { self == .black ? "Black" : "White" }
}

struct Position: Hashable, Codable, Sendable, Identifiable {
    let r: Int
    let c: Int

    var id: String { "\(r)-\(c)" }
    var coordinate: String {
        let scalar = UnicodeScalar(65 + c).map(Character.init) ?? "?"
        return "\(scalar)\(r + 1)"
    }
}

enum MoveController: String, Codable, Sendable {
    case human
    case ai
}

struct ClockSnapshot: Codable, Equatable, Sendable {
    var black: TimeInterval = 0
    var white: TimeInterval = 0
    var started = false

    subscript(player: Player) -> TimeInterval {
        get { player == .black ? black : white }
        set {
            if player == .black { black = newValue } else { white = newValue }
        }
    }
}

struct MoveRecord: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let pos: Position
    let player: Player
    let controller: MoveController
    let mode: GameMode
    let clockBefore: ClockSnapshot
}

enum GameOutcome: Codable, Equatable, Sendable {
    case ongoing
    case draw
    case win(player: Player, line: [Position])

    var isTerminal: Bool { self != .ongoing }
    var winner: Player? {
        if case let .win(player, _) = self { return player }
        return nil
    }
    var winningLine: [Position] {
        if case let .win(_, line) = self { return line }
        return []
    }
}

struct GameConfiguration: Codable, Equatable, Sendable {
    var mode: GameMode = .pvp
    var boardSize = 15
    var difficulty: AIDifficulty = .medium
    var humanSide: Player = .white

    mutating func normalize() {
        boardSize = min(25, max(5, boardSize))
        if boardSize.isMultiple(of: 2) { boardSize += boardSize == 25 ? -1 : 1 }
    }
}

struct ModeTransition: Codable, Equatable, Sendable {
    let moveIndex: Int
    let from: GameMode
    let to: GameMode
}

struct GameSession: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion = Self.schemaVersion
    var id = UUID()
    var configuration: GameConfiguration
    var board: [CellState]
    var current: Player = .black
    var moves: [MoveRecord] = []
    var clocks = ClockSnapshot()
    var turnStartedAt: Date?
    var outcome: GameOutcome = .ongoing
    var modeTransitions: [ModeTransition] = []
    var archived = false

    init(configuration: GameConfiguration = .init()) {
        var safeConfiguration = configuration
        safeConfiguration.normalize()
        self.configuration = safeConfiguration
        self.board = Array(repeating: .empty, count: safeConfiguration.boardSize * safeConfiguration.boardSize)
    }

    var boardSize: Int { configuration.boardSize }
    var isValid: Bool {
        guard schemaVersion == Self.schemaVersion,
              (5...25).contains(boardSize),
              !boardSize.isMultiple(of: 2),
              board.count == boardSize * boardSize,
              clocks.black.isFinite, clocks.black >= 0,
              clocks.white.isFinite, clocks.white >= 0,
              moves.allSatisfy({ contains($0.pos) }),
              Set(moves.map(\.pos)).count == moves.count,
              moves.enumerated().allSatisfy({ offset, move in
                  move.player == (offset.isMultiple(of: 2) ? .black : .white) &&
                  state(at: move.pos).player == move.player
              }),
              board.filter({ $0 != .empty }).count == moves.count else { return false }

        let expectedNext: Player = moves.count.isMultiple(of: 2) ? .black : .white
        switch outcome {
        case .ongoing:
            return current == expectedNext
        case .draw:
            return board.allSatisfy { $0 != .empty } && current == moves.last?.player
        case let .win(player, line):
            return current == player &&
                moves.last?.player == player &&
                line.count >= 5 &&
                line.allSatisfy { state(at: $0).player == player } &&
                moves.last.flatMap { winningLine(from: $0.pos, player: player) } == line
        }
    }

    var aiPlayer: Player { configuration.humanSide.next }
    var isAITurn: Bool {
        configuration.mode == .ai && current == aiPlayer && outcome == .ongoing
    }

    func contains(_ position: Position) -> Bool {
        (0..<boardSize).contains(position.r) && (0..<boardSize).contains(position.c)
    }

    func index(of position: Position) -> Int? {
        guard contains(position) else { return nil }
        return position.r * boardSize + position.c
    }

    func state(at position: Position) -> CellState {
        guard let index = index(of: position), board.indices.contains(index) else { return .empty }
        return board[index]
    }

    func elapsed(for player: Player, now: Date = .now) -> TimeInterval {
        var value = clocks[player]
        if clocks.started, outcome == .ongoing, current == player, let turnStartedAt {
            value += max(0, now.timeIntervalSince(turnStartedAt))
        }
        return value
    }

    func materializedClocks(now: Date) -> ClockSnapshot {
        var result = clocks
        guard result.started, outcome == .ongoing, let turnStartedAt else { return result }
        result[current] += max(0, now.timeIntervalSince(turnStartedAt))
        return result
    }

    @discardableResult
    mutating func place(
        at position: Position,
        controller: MoveController,
        now: Date = .now
    ) -> Bool {
        guard outcome == .ongoing,
              let index = index(of: position),
              board[index] == .empty else { return false }

        let snapshot = materializedClocks(now: now)
        let movingPlayer = current
        board[index] = movingPlayer.cellState
        moves.append(MoveRecord(
            pos: position,
            player: movingPlayer,
            controller: controller,
            mode: configuration.mode,
            clockBefore: snapshot
        ))

        clocks = snapshot
        if !clocks.started { clocks.started = true }

        if let line = winningLine(from: position, player: movingPlayer) {
            outcome = .win(player: movingPlayer, line: line)
            turnStartedAt = nil
        } else if board.allSatisfy({ $0 != .empty }) {
            outcome = .draw
            turnStartedAt = nil
        } else {
            current = movingPlayer.next
            turnStartedAt = now
        }
        return true
    }

    @discardableResult
    mutating func undoOne(now: Date = .now) -> MoveRecord? {
        guard let move = moves.popLast(), let index = index(of: move.pos) else { return nil }
        board[index] = .empty
        current = move.player
        clocks = move.clockBefore
        outcome = .ongoing
        archived = false
        turnStartedAt = clocks.started ? now : nil
        return move
    }

    mutating func pause(now: Date = .now) {
        clocks = materializedClocks(now: now)
        turnStartedAt = nil
    }

    mutating func resume(now: Date = .now) {
        guard clocks.started, outcome == .ongoing else { return }
        turnStartedAt = now
    }

    mutating func setMode(_ newMode: GameMode) {
        let oldMode = configuration.mode
        guard oldMode != newMode else { return }
        configuration.mode = newMode
        modeTransitions.append(.init(moveIndex: moves.count, from: oldMode, to: newMode))
    }

    func winningLine(from position: Position, player: Player) -> [Position]? {
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        for (dr, dc) in directions {
            var line = Array(collect(from: position, dr: -dr, dc: -dc, player: player).reversed())
            line.append(position)
            line.append(contentsOf: collect(from: position, dr: dr, dc: dc, player: player))
            if line.count >= 5 { return line }
        }
        return nil
    }

    private func collect(from origin: Position, dr: Int, dc: Int, player: Player) -> [Position] {
        var result: [Position] = []
        var position = Position(r: origin.r + dr, c: origin.c + dc)
        while contains(position), state(at: position).player == player {
            result.append(position)
            position = Position(r: position.r + dr, c: position.c + dc)
        }
        return result
    }
}

