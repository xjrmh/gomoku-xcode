import Foundation

@main
struct Evaluation {
    static func emit(_ value: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        fflush(stdout)
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    static func move(_ session: GameSession, _ difficulty: AIDifficulty, seed: UInt64, diagnostic: Bool = false, budget: Int = 750) -> (Position, Double) {
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .milliseconds(budget))
        let position: Position?
        if diagnostic {
            InstrumentedAIEngine.reset()
            position = InstrumentedAIEngine.computeBestMove(for: session.current, board: session.board, size: session.boardSize, difficulty: difficulty, deadline: deadline, seed: seed)
        } else {
            position = AIEngine.computeBestMove(for: session.current, board: session.board, size: session.boardSize, difficulty: difficulty, deadline: deadline, seed: seed)
        }
        guard let position, session.board[position.r * session.boardSize + position.c] == .empty else {
            fatalError("Engine returned an invalid move")
        }
        return (position, milliseconds(start.duration(to: .now)))
    }

    static let openings: [[(Int, Int)]] = [
        [],
        [(0, 0), (0, 1)],
        [(0, 0), (1, 1)],
        [(0, 0), (0, 2)],
        [(0, 0), (1, 2)],
        [(0, 0), (1, 0), (0, 1), (1, 1)],
        [(0, 0), (1, 1), (-1, 1), (1, -1)],
        [(0, 0), (0, 2), (1, 1), (-1, 1)],
        [(0, 0), (1, 2), (-1, 0), (0, 2)],
        [(0, 0), (-1, -1), (1, 0), (-1, 1)],
    ]

    static func session(size: Int, opening: Int) -> GameSession {
        var result = GameSession(configuration: .init(mode: .pvp, boardSize: size))
        for (r, c) in openings[opening] {
            precondition(result.place(at: Position(r: size / 2 + r, c: size / 2 + c), controller: .human))
        }
        return result
    }

    static func basics() {
        var checks = 0
        var failures = 0
        for size in [5, 9, 15, 19, 25] {
            for difficulty in AIDifficulty.allCases {
                let empty = Array(repeating: CellState.empty, count: size * size)
                let center = AIEngine.computeBestMove(for: .black, board: empty, size: size, difficulty: difficulty)
                checks += 1
                if center != Position(r: size / 2, c: size / 2) { failures += 1 }
                for player in Player.allCases {
                    for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
                        var board = empty
                        let r = dr == 0 ? size / 2 : 0
                        let c = dc < 0 ? 4 : dc == 0 ? size / 2 : 0
                        // Four stones start at the edge: there is exactly one winning continuation.
                        for offset in 0..<4 { board[(r + dr * offset) * size + c + dc * offset] = player.cellState }
                        let expected = Position(r: r + dr * 4, c: c + dc * 4)
                        for side in [player, player.next] {
                            let selected = AIEngine.computeBestMove(for: side, board: board, size: size, difficulty: difficulty)
                            checks += 1
                            if selected != expected { failures += 1 }
                        }
                    }
                }
            }
        }
        emit(["event": "basics", "checks": checks, "failures": failures,
              "scope": "synthetic empty-board and unique immediate win/block positions; not a legal-history strength test"])
    }

    static func profile() {
        for size in [9, 15, 19, 25] {
            for opening in [1, 5, 6, 8] {
                var game = session(size: size, opening: opening)
                // Build legally reachable midgames with medium moves before profiling.
                for _ in 0..<8 {
                    if game.outcome.isTerminal { break }
                    let (position, _) = move(game, .medium, seed: 1)
                    precondition(game.place(at: position, controller: .human))
                }
                if game.outcome.isTerminal { continue }
                let (medium, mediumMS) = move(game, .medium, seed: 1)
                let (hard, hardMS) = move(game, .hard, seed: 1, diagnostic: true)
                emit(["event": "profile", "size": size, "opening": opening, "stones": game.moves.count,
                      "medium": medium.coordinate, "mediumMS": mediumMS, "hard": hard.coordinate, "hardMS": hardMS,
                      "completedDepth": InstrumentedAIEngine.completedDepth, "nodes": InstrumentedAIEngine.nodes,
                      "verifiedCompletedDepth": InstrumentedAIEngine.verifiedCompletedDepth,
                      "cacheHits": InstrumentedAIEngine.cacheHits, "timedOut": InstrumentedAIEngine.timedOut,
                      "committedAfterTimeout": InstrumentedAIEngine.committedAfterTimeout,
                      "lastDepthRootMoves": InstrumentedAIEngine.rootMovesCompleted,
                      "history": game.moves.map { $0.pos.coordinate }])
            }
        }
    }

    static func tournament(size: Int, pairs: Int, opponent: AIDifficulty, startOpening: Int) {
        var wins: [String: Int] = ["hard": 0, opponent.rawValue: 0, "draw": 0]
        var blackWins = 0
        for opening in startOpening..<min(startOpening + pairs, openings.count) {
            for hardSide in Player.allCases {
                var game = session(size: size, opening: opening)
                var decisions: [[String: Any]] = []
                while !game.outcome.isTerminal {
                    let side = game.current
                    let difficulty: AIDifficulty = side == hardSide ? .hard : opponent
                    // Match the app's deterministic seed exactly.
                    let seed = UInt64(game.moves.count + game.boardSize)
                    let (position, elapsed) = move(game, difficulty, seed: seed)
                    decisions.append(["ply": game.moves.count + 1, "side": side.name, "difficulty": difficulty.rawValue,
                                      "move": position.coordinate, "ms": elapsed])
                    precondition(game.place(at: position, controller: .human))
                }
                let winner = game.outcome.winner.map { $0 == hardSide ? "hard" : opponent.rawValue } ?? "draw"
                wins[winner, default: 0] += 1
                if game.outcome.winner == .black { blackWins += 1 }
                emit(["event": "game", "size": size, "opening": opening, "hardSide": hardSide.name,
                      "winner": winner, "winnerSide": game.outcome.winner?.name ?? "draw", "plies": game.moves.count,
                      "openingMoves": openings[opening].map { Position(r: size / 2 + $0.0, c: size / 2 + $0.1).coordinate },
                      "decisions": decisions, "runningWins": wins])
            }
        }
        emit(["event": "tournament", "size": size, "pairs": min(pairs, openings.count), "wins": wins,
              "blackWins": blackWins, "budgetMS": 750, "instrumented": false,
              "scope": "deterministic local engine-vs-engine matches with paired colors; no human/Elo claim"])
    }

    static func historySession(size: Int, coordinates: [String]) -> GameSession {
        var game = GameSession(configuration: .init(mode: .pvp, boardSize: size))
        for coordinate in coordinates {
            let c = Int(coordinate.utf8.first!) - 65
            let r = Int(coordinate.dropFirst())! - 1
            precondition(game.place(at: Position(r: r, c: c), controller: .human))
            precondition(!game.outcome.isTerminal)
        }
        return game
    }

    // Independent full-board win/fork verifier. It does not use engine heuristics,
    // candidate beams, transposition tables, or search scores.
    static func wins(_ board: [CellState], size: Int, position: Position, player: Player) -> Bool {
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var count = 1
            for sign in [-1, 1] {
                var r = position.r + sign * dr
                var c = position.c + sign * dc
                while (0..<size).contains(r), (0..<size).contains(c), board[r * size + c] == player.cellState {
                    count += 1; r += sign * dr; c += sign * dc
                }
            }
            if count >= 5 { return true }
        }
        return false
    }

    static func winningMoves(_ board: [CellState], size: Int, player: Player) -> [Position] {
        board.indices.filter { board[$0] == .empty }.compactMap { index in
            let position = Position(r: index / size, c: index % size)
            return wins(board, size: size, position: position, player: player) ? position : nil
        }
    }

    static func losingReply(_ board: [CellState], size: Int, defender: Player) -> (Position, [Position])? {
        let attacker = defender.next
        for index in board.indices where board[index] == .empty {
            let reply = Position(r: index / size, c: index % size)
            if wins(board, size: size, position: reply, player: attacker) { return (reply, []) }
            var next = board
            next[index] = attacker.cellState
            let continuations = winningMoves(next, size: size, player: attacker)
            if continuations.count >= 2 && winningMoves(next, size: size, player: defender).isEmpty {
                return (reply, continuations)
            }
        }
        return nil
    }

    static func tactical() {
        let history = ["E4", "F8", "H5", "G8", "F9", "I8", "K4", "H6", "D7", "H7", "D12", "H9", "F11", "I11", "J5", "J6", "E5", "L5"]
        let game = historySession(size: 15, coordinates: history)
        var safe: [String] = []
        for index in game.board.indices where game.board[index] == .empty {
            let defense = Position(r: index / 15, c: index % 15)
            var next = game.board
            next[index] = game.current.cellState
            if wins(game.board, size: 15, position: defense, player: game.current) || losingReply(next, size: 15, defender: game.current) == nil {
                safe.append(defense.coordinate)
            }
        }
        emit(["event": "tacticalFixture", "size": 15, "toMove": game.current.name,
              "history": history, "survivingMovesAgainstOneReplyWinOrFork": safe])
        for difficulty in AIDifficulty.allCases {
            for budget in difficulty == .hard ? [750, 3000, 30000] : [750] {
                let (selected, elapsed) = move(game, difficulty, seed: 33, diagnostic: difficulty == .hard, budget: budget)
                var next = game.board
                next[selected.r * 15 + selected.c] = game.current.cellState
                let reply = losingReply(next, size: 15, defender: game.current)
                emit(["event": "tacticalResult", "difficulty": difficulty.rawValue, "budgetMS": budget,
                      "move": selected.coordinate, "ms": elapsed, "provenImmediateOrForkLoss": reply != nil,
                      "winningReply": reply?.0.coordinate ?? "none", "winningContinuations": reply?.1.map { $0.coordinate } ?? [],
                      "completedDepth": InstrumentedAIEngine.completedDepth,
                      "verifiedCompletedDepth": InstrumentedAIEngine.verifiedCompletedDepth])
            }
        }
    }

    static func correctness() {
        let history = ["A3", "E1", "G3", "F1", "A5", "B2", "E6", "C6", "D7", "F6"]
        let game = historySession(size: 7, coordinates: history)
        for iteration in 1...3 {
            let (original, originalMS) = move(game, .hard, seed: 1, budget: 30000)
            let start = ContinuousClock.now
            let control = NoCacheAIEngine.computeBestMove(for: game.current, board: game.board, size: 7,
                difficulty: .hard, deadline: start.advanced(by: .seconds(30)), seed: 1)!
            emit(["event": "cacheCounterexample", "iteration": iteration, "size": 7, "history": history,
                  "originalMove": original.coordinate, "originalMS": originalMS,
                  "noCacheMove": control.coordinate, "noCacheMS": milliseconds(start.duration(to: .now)),
                  "budgetMS": 30000, "controlChange": "remove only cache lookup/write; same depth/beam/evaluator"])
        }
        var board = Array(repeating: CellState.empty, count: 49)
        board[3 * 7 + 3] = .black
        let values = InstrumentedAIEngine.timeoutProbe(board: board, size: 7, root: .black)
        emit(["event": "timeoutSignCounterexample", "size": 7, "black": ["D4"], "root": "Black", "player": "White", "depth": 0,
              "liveValue": values["live"]!, "expiredValue": values["expired"]!])
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first ?? "profile" {
        case "basics": basics()
        case "profile": profile()
        case "tactical": tactical()
        case "correctness": correctness()
        case "tournament": tournament(size: args.count > 1 ? Int(args[1])! : 15,
                                      pairs: args.count > 2 ? Int(args[2])! : 10,
                                      opponent: args.count > 3 ? AIDifficulty(rawValue: args[3])! : .medium,
                                      startOpening: args.count > 4 ? Int(args[4])! : 0)
        default: fatalError("Use basics, profile, tactical, correctness, or tournament [size] [pairs] [easy|medium] [startOpening]")
        }
    }
}
