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

    enum EngineVersion { case production, baseline }

    static func move(_ session: GameSession, _ difficulty: AIDifficulty, seed: UInt64,
                     budget: Int? = nil, engine: EngineVersion = .production) -> (Position, Double) {
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .milliseconds(budget ?? (difficulty == .hard ? 750 : 350)))
        let position: Position?
        switch engine {
        case .production:
            position = AIEngine.computeBestMove(for: session.current, board: session.board,
                size: session.boardSize, difficulty: difficulty, deadline: deadline, seed: seed)
        case .baseline:
            position = BaselineAIEngine.computeBestMove(for: session.current, board: session.board,
                size: session.boardSize, difficulty: difficulty, deadline: deadline, seed: seed)
        }
        guard let position, session.contains(position), session.state(at: position) == .empty else {
            fatalError("Engine returned an invalid move")
        }
        return (position, milliseconds(start.duration(to: .now)))
    }

    static func analyze(_ session: GameSession, budget: Int = 750,
                        options: AIEngine.SearchOptions = .init()) -> (AIEngine.SearchResult, Double) {
        let start = ContinuousClock.now
        let result = AIEngine.analyzeMove(for: session.current, board: session.board,
            size: session.boardSize, difficulty: .hard,
            deadline: start.advanced(by: .milliseconds(budget)), seed: UInt64(session.moves.count + session.boardSize),
            searchOptions: options)
        guard let position = result.position, session.contains(position), session.state(at: position) == .empty else {
            fatalError("Engine diagnostics returned an invalid move")
        }
        return (result, milliseconds(start.duration(to: .now)))
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
                let (result, hardMS) = analyze(game)
                emit(["event": "profile", "size": size, "opening": opening, "stones": game.moves.count,
                      "medium": medium.coordinate, "mediumMS": mediumMS,
                      "hard": result.position!.coordinate, "hardMS": hardMS,
                      "completedDepth": result.completedDepth, "nodes": result.visitedNodes,
                      "interrupted": result.interrupted, "diagnostics": "native per-call result",
                      "history": game.moves.map { $0.pos.coordinate }])
            }
        }
    }

    static func tournament(size: Int, pairs: Int, opponent: String, startOpening: Int) {
        precondition((5...25).contains(size) && !size.isMultiple(of: 2))
        precondition(pairs > 0 && (0..<openings.count).contains(startOpening))
        precondition(["easy", "medium", "baseline"].contains(opponent))
        let baselineOpponent = opponent == "baseline"
        let opponentDifficulty: AIDifficulty = baselineOpponent ? .hard : AIDifficulty(rawValue: opponent)!
        let opponentLabel = baselineOpponent ? "baselineHard" : opponent
        let actualPairs = min(pairs, openings.count - startOpening)
        var wins: [String: Int] = ["hard": 0, opponentLabel: 0, "draw": 0]
        var blackWins = 0
        for opening in startOpening..<(startOpening + actualPairs) {
            for hardSide in Player.allCases {
                var game = session(size: size, opening: opening)
                var decisions: [[String: Any]] = []
                while !game.outcome.isTerminal {
                    let side = game.current
                    let currentHard = side == hardSide
                    let difficulty: AIDifficulty = currentHard ? .hard : opponentDifficulty
                    let engine: EngineVersion = !currentHard && baselineOpponent ? .baseline : .production
                    // Match the app's deterministic seed and per-difficulty budget exactly.
                    let seed = UInt64(game.moves.count + game.boardSize)
                    let (position, elapsed) = move(game, difficulty, seed: seed, engine: engine)
                    decisions.append(["ply": game.moves.count + 1, "side": side.name,
                                      "difficulty": difficulty.rawValue,
                                      "engine": !currentHard && baselineOpponent ? "baseline" : "current",
                                      "move": position.coordinate, "ms": elapsed])
                    precondition(game.place(at: position, controller: .human))
                }
                let winner = game.outcome.winner.map { $0 == hardSide ? "hard" : opponentLabel } ?? "draw"
                wins[winner, default: 0] += 1
                if game.outcome.winner == .black { blackWins += 1 }
                emit(["event": "game", "size": size, "opening": opening, "hardSide": hardSide.name,
                      "opponent": opponentLabel, "winner": winner,
                      "winnerSide": game.outcome.winner?.name ?? "draw", "plies": game.moves.count,
                      "openingMoves": openings[opening].map { Position(r: size / 2 + $0.0, c: size / 2 + $0.1).coordinate },
                      "decisions": decisions, "runningWins": wins])
            }
        }
        emit(["event": "tournament", "size": size, "pairs": actualPairs, "games": actualPairs * 2,
              "startOpening": startOpening, "opponent": opponentLabel, "wins": wins,
              "blackWins": blackWins, "hardBudgetMS": 750,
              "opponentBudgetMS": opponentDifficulty == .hard ? 750 : 350, "instrumented": false,
              "scope": "local engine-vs-engine matches with paired colors and fixed openings; no human/Elo claim"])
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
            for budget in difficulty == .hard ? [750, 3000, 30000] : [350] {
                for iteration in 1...(difficulty == .hard && budget == 750 ? 5 : 1) {
                let (selected, elapsed) = move(game, difficulty, seed: 33, budget: budget)
                var next = game.board
                next[selected.r * 15 + selected.c] = game.current.cellState
                let reply = wins(game.board, size: 15, position: selected, player: game.current) ? nil : losingReply(next, size: 15, defender: game.current)
                emit(["event": "tacticalResult", "difficulty": difficulty.rawValue, "budgetMS": budget,
                      "iteration": iteration, "instrumented": false,
                      "move": selected.coordinate, "ms": elapsed, "provenImmediateOrForkLoss": reply != nil,
                      "winningReply": reply?.0.coordinate ?? "none", "winningContinuations": reply?.1.map { $0.coordinate } ?? [],
                      "history": history])
                }
            }
        }
        let (result, elapsed) = analyze(game)
        emit(["event": "tacticalSearchProfile", "move": result.position!.coordinate, "ms": elapsed,
              "completedDepth": result.completedDepth, "nodes": result.visitedNodes,
              "interrupted": result.interrupted, "diagnostics": "native per-call result"])
    }

    static func tacticalSymmetries() {
        let history = ["E4", "F8", "H5", "G8", "F9", "I8", "K4", "H6", "D7", "H7", "D12", "H9", "F11", "I11", "J5", "J6", "E5", "L5"]
        var checks = 0
        var failures = 0
        for reflected in [false, true] {
            for rotations in 0..<4 {
                for (dr, dc) in [(0, 0), (1, 1), (-2, -1)] {
                    let transformed = history.map { coordinate -> String in
                        var r = Int(coordinate.dropFirst())! - 1
                        var c = Int(coordinate.utf8.first!) - 65
                        if reflected { c = 14 - c }
                        for _ in 0..<rotations { (r, c) = (c, 14 - r) }
                        return Position(r: r + dr, c: c + dc).coordinate
                    }
                    let game = historySession(size: 15, coordinates: transformed)
                    let expected = Position(r: 7 + dr, c: 7 + dc)
                    let (selected, elapsed) = move(game, .hard, seed: UInt64(game.moves.count + 15))
                    var next = game.board
                    next[selected.r * 15 + selected.c] = game.current.cellState
                    let allowsLoss = losingReply(next, size: 15, defender: game.current) != nil
                    checks += 1
                    if selected != expected || allowsLoss { failures += 1 }
                    emit(["event": "tacticalSymmetry", "reflected": reflected, "quarterTurns": rotations,
                          "rowOffset": dr, "columnOffset": dc, "expected": expected.coordinate,
                          "selected": selected.coordinate, "ms": elapsed, "allowsProvenForkLoss": allowsLoss,
                          "history": transformed])
                }
            }
        }
        emit(["event": "tacticalSymmetries", "checks": checks, "failures": failures])
        precondition(failures == 0, "A transformed fork-defense fixture failed")
    }

    static func correctness() {
        let history = ["A3", "E1", "G3", "F1", "A5", "B2", "E6", "C6", "D7", "F6"]
        let game = historySession(size: 7, coordinates: history)
        var failures = 0
        for depth in 1...4 {
            let (cached, cachedMS) = analyze(game, budget: 30000,
                options: .init(maxDepth: depth, useTranspositionTable: true))
            let (uncached, uncachedMS) = analyze(game, budget: 30000,
                options: .init(maxDepth: depth, useTranspositionTable: false))
            let comparable = !cached.interrupted && !uncached.interrupted && cached.completedDepth == uncached.completedDepth
            let agrees = comparable && cached.position == uncached.position && cached.score == uncached.score
            if !agrees { failures += 1 }
            emit(["event": "cacheEquivalence", "size": 7, "history": history, "requestedDepth": depth,
                  "cachedMove": cached.position!.coordinate, "cachedMS": cachedMS,
                  "cachedDepth": cached.completedDepth, "cachedNodes": cached.visitedNodes,
                  "cachedScore": cached.score.map { $0 as Any } ?? NSNull(),
                  "noCacheMove": uncached.position!.coordinate, "noCacheMS": uncachedMS,
                  "noCacheDepth": uncached.completedDepth, "noCacheNodes": uncached.visitedNodes,
                  "noCacheScore": uncached.score.map { $0 as Any } ?? NSNull(),
                  "budgetMS": 30000, "completedComparableSearches": comparable, "agrees": agrees,
                  "controlChange": "per-call useTranspositionTable option; same production search"])
        }
        let sparse = historySession(size: 7, coordinates: ["D4"])
        let (expired, expiredMS) = analyze(sparse, budget: -1)
        emit(["event": "expiredDeadlineFallback", "size": 7, "history": ["D4"],
              "position": expired.position!.coordinate, "completedDepth": expired.completedDepth,
              "nodes": expired.visitedNodes, "interrupted": expired.interrupted, "ms": expiredMS])
        emit(["event": "correctness", "cacheComparisons": 4, "failures": failures])
        precondition(failures == 0, "Completed cached and uncached searches disagreed")
    }

    static func difficultyEquivalence() {
        var checks = 0
        var failures = 0
        var positions = 0
        for size in [5, 7, 9, 15, 19, 25] {
            for opening in [0, 1, 5, 6, 8] {
                var game = session(size: size, opening: opening)
                for ply in 0..<16 {
                    if game.outcome.isTerminal { break }
                    positions += 1
                    for difficulty in [AIDifficulty.easy, .medium] {
                        for seed in [UInt64(0), 1, 42, UInt64(game.moves.count + size)] {
                            let current = AIEngine.computeBestMove(for: game.current, board: game.board,
                                size: size, difficulty: difficulty, deadline: .now.advanced(by: .seconds(5)), seed: seed)
                            let baseline = BaselineAIEngine.computeBestMove(for: game.current, board: game.board,
                                size: size, difficulty: difficulty, deadline: .now.advanced(by: .seconds(5)), seed: seed)
                            checks += 1
                            if current != baseline {
                                failures += 1
                                emit(["event": "difficultyEquivalenceFailure", "size": size,
                                      "opening": opening, "difficulty": difficulty.rawValue,
                                      "seed": seed, "current": current?.coordinate ?? "none",
                                      "baseline": baseline?.coordinate ?? "none",
                                      "history": game.moves.map { $0.pos.coordinate }])
                            }
                        }
                    }
                    let difficulty: AIDifficulty = ply.isMultiple(of: 3) ? .easy : .medium
                    let (position, _) = move(game, difficulty,
                        seed: UInt64(game.moves.count * 37 + opening * 11 + size), engine: .baseline)
                    precondition(game.place(at: position, controller: .human))
                }
            }
        }
        emit(["event": "difficultyEquivalence", "legalPositions": positions,
              "seededMoveComparisons": checks, "failures": failures,
              "scope": "current Easy/Medium vs exact prior engine; same legal boards, player and seed"])
        precondition(failures == 0, "Easy or Medium behavior changed")
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first ?? "profile" {
        case "basics": basics()
        case "profile": profile()
        case "tactical": tactical()
        case "correctness": correctness()
        case "tactical-symmetries": tacticalSymmetries()
        case "difficulty-equivalence": difficultyEquivalence()
        case "tournament": tournament(size: args.count > 1 ? Int(args[1])! : 15,
                                      pairs: args.count > 2 ? Int(args[2])! : 10,
                                      opponent: args.count > 3 ? args[3] : "medium",
                                      startOpening: args.count > 4 ? Int(args[4])! : 0)
        default: fatalError("Use basics, profile, tactical, tactical-symmetries, difficulty-equivalence, correctness, or tournament [size] [pairs] [easy|medium|baseline] [startOpening]")
        }
    }
}
