import Foundation

enum AIEngine {
    struct SearchOptions: Sendable {
        var maxDepth = 6
        var useTranspositionTable = true
        var threatExtensionDepth = 4
    }

    struct SearchResult: Sendable {
        let position: Position?
        let completedDepth: Int
        let visitedNodes: Int
        let interrupted: Bool
        let score: Double?
    }

    private static let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
    private static let winScore = 10_000_000.0

    static func bestMove(
        for player: Player,
        session: GameSession,
        difficulty: AIDifficulty,
        deadline: ContinuousClock.Instant,
        seed: UInt64
    ) async -> Position? {
        let computation = Task.detached(priority: .userInitiated) {
            computeBestMove(
                for: player,
                board: session.board,
                size: session.boardSize,
                difficulty: difficulty,
                deadline: deadline,
                seed: seed
            )
        }
        return await withTaskCancellationHandler {
            await computation.value
        } onCancel: {
            computation.cancel()
        }
    }

    static func computeBestMove(
        for player: Player,
        board: [CellState],
        size: Int,
        difficulty: AIDifficulty,
        deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(1)),
        seed: UInt64 = 1,
        searchOptions: SearchOptions = .init()
    ) -> Position? {
        analyzeMove(for: player, board: board, size: size, difficulty: difficulty,
                    deadline: deadline, seed: seed, searchOptions: searchOptions).position
    }

    static func analyzeMove(
        for player: Player,
        board: [CellState],
        size: Int,
        difficulty: AIDifficulty,
        deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(1)),
        seed: UInt64 = 1,
        searchOptions: SearchOptions = .init()
    ) -> SearchResult {
        func immediate(_ position: Position?) -> SearchResult {
            SearchResult(position: position, completedDepth: 0, visitedNodes: 0,
                         interrupted: false, score: nil)
        }
        guard (5...25).contains(size), board.count == size * size else { return immediate(nil) }
        let empties = emptyPositions(board, size)
        guard !empties.isEmpty else { return immediate(nil) }
        if empties.count == board.count {
            return immediate(Position(r: size / 2, c: size / 2))
        }

        let candidates = candidatePositions(board, size)
        let opponent = player.next

        if let win = candidates.first(where: { formsFive(board, size, $0, player) }) { return immediate(win) }
        if let block = candidates.first(where: { formsFive(board, size, $0, opponent) }) { return immediate(block) }

        switch difficulty {
        case .easy:
            var generator = SeededGenerator(seed: seed)
            let ranked = candidates
                .map { ($0, heuristic(board, size, $0, player) + heuristic(board, size, $0, opponent) * 0.65) }
                .sorted { $0.1 > $1.1 }
            let pool = Array(ranked.prefix(min(8, ranked.count)))
            guard let choice = pool.randomElement(using: &generator) else { return immediate(candidates.first) }
            return immediate(choice.0)

        case .medium:
            return immediate(rankedCandidates(board, size, candidates, player).first?.position)

        case .hard:
            return hardMove(board: board, size: size, candidates: candidates, player: player,
                            deadline: deadline, options: searchOptions)
        }
    }

    private static func hardMove(
        board: [CellState],
        size: Int,
        candidates: [Position],
        player: Player,
        deadline: ContinuousClock.Instant,
        options: SearchOptions
    ) -> SearchResult {
        var mutableBoard = board
        let assessed = assessedMoves(board, size, candidates, player)
        // Mandatory tactics precede the beam and the time-limited search, so even
        // its fallback cannot overlook a fork that the opponent already has.
        if let fork = assessed.first(where: { $0.ownWinningPoints.count >= 2 }) {
            return SearchResult(position: fork.position, completedDepth: 0, visitedNodes: 0,
                                interrupted: false, score: winScore - 2)
        }
        let safe = forkDefenses(&mutableBoard, size, assessed, player)
        let ordered = Array((safe.isEmpty ? assessed : safe).prefix(18))
        guard let fallback = ordered.first?.position else {
            return SearchResult(position: candidates.first, completedDepth: 0,
                                visitedNodes: 0, interrupted: false, score: nil)
        }

        var best = fallback
        var bestScore: Double?
        var completedDepth = 0
        var state = SearchState(deadline: deadline, options: options)
        for depth in 1...max(1, min(12, options.maxDepth)) {
            guard state.canContinue() else { break }
            var depthBest = best
            var depthScore = -Double.infinity
            var completed = true
            for item in ordered {
                guard state.canContinue() else { completed = false; break }
                let index = item.position.r * size + item.position.c
                mutableBoard[index] = player.cellState
                let child = negamax(board: &mutableBoard, size: size, player: player.next,
                                    depth: depth - 1, extensions: max(0, min(8, options.threatExtensionDepth)),
                                    ply: 1, alpha: -.infinity, beta: -depthScore, state: &state)
                mutableBoard[index] = .empty
                guard let child, state.canContinue() else { completed = false; break }
                let score = -child
                // A fail-low bound equal to the best score is not an exact tie.
                if score > depthScore { depthScore = score; depthBest = item.position }
            }
            guard completed else { break }
            best = depthBest
            bestScore = depthScore
            completedDepth = depth
            if abs(depthScore) >= winScore - 32 { break }
        }
        return SearchResult(position: best, completedDepth: completedDepth,
                            visitedNodes: state.visitedNodes, interrupted: state.interrupted, score: bestScore)
    }

    private static func negamax(
        board: inout [CellState],
        size: Int,
        player: Player,
        depth: Int,
        extensions: Int,
        ply: Int,
        alpha: Double,
        beta: Double,
        state: inout SearchState
    ) -> Double? {
        state.visitedNodes += 1
        guard state.canContinue() else { return nil }
        let key = SearchKey(hash: boardHash(board), player: player, depth: depth, extensions: extensions)
        var localAlpha = alpha
        var localBeta = beta
        var cachedMove: Position?
        if state.options.useTranspositionTable, let cached = state.table[key] {
            cachedMove = cached.bestMove
            switch cached.bound {
            case .exact: return cached.value
            case .lower: localAlpha = max(localAlpha, cached.value)
            case .upper: localBeta = min(localBeta, cached.value)
            }
            if localAlpha >= localBeta { return cached.value }
        }

        let assessed = assessedMoves(board, size, candidatePositions(board, size), player)
        guard state.canContinue() else { return nil }
        if assessed.isEmpty { return 0 }
        // Check terminal threats even at the horizon. A forcing line must not
        // disappear just because it crosses the nominal depth limit.
        if assessed.contains(where: { formsFive(board, size, $0.position, player) }) {
            return winScore - Double(ply)
        }
        let losses = assessed.filter { formsFive(board, size, $0.position, player.next) }
        if losses.count >= 2 { return -winScore + Double(ply + 1) }

        var moves: [AssessedMove]
        var mandatory = false
        if let block = losses.first {
            moves = [block]
            mandatory = true
        } else {
            if assessed.contains(where: { $0.ownWinningPoints.count >= 2 }) {
                return winScore - Double(ply + 2)
            }
            moves = forkDefenses(&board, size, assessed, player)
            guard state.canContinue() else { return nil }
            if moves.isEmpty { return -winScore + Double(ply + 3) }
            mandatory = moves.count < assessed.count
        }

        var standPat: Double?
        if depth <= 0 {
            let staticScore = evaluateMoves(assessed)
            // Resolve a final unique block before evaluating. Its child gets
            // -1 extensions, so this cannot grow into an unbounded threat chain.
            guard extensions > 0 || (extensions == 0 && losses.count == 1) else { return staticScore }
            if !mandatory {
                moves = moves.filter { !$0.ownWinningPoints.isEmpty }
                if moves.isEmpty { return staticScore }
                standPat = staticScore
            }
        }
        let width = depth <= 0 ? 4 : 10
        moves = Array(moves.prefix(width))
        if let cachedMove, let index = moves.firstIndex(where: { $0.position == cachedMove }) {
            moves.swapAt(0, index)
        }
        var value = -Double.infinity
        var bestMove: Position?
        if let standPat {
            value = standPat
            localAlpha = max(localAlpha, value)
        }
        for item in moves where localAlpha < localBeta {
            guard state.canContinue() else { return nil }
            let index = item.position.r * size + item.position.c
            board[index] = player.cellState
            let result = negamax(board: &board, size: size, player: player.next,
                                 depth: max(0, depth - 1), extensions: depth <= 0 ? extensions - 1 : extensions,
                                 ply: ply + 1, alpha: -localBeta, beta: -localAlpha, state: &state)
            board[index] = .empty
            guard let result, state.canContinue() else { return nil }
            let child = -result
            if child > value { value = child; bestMove = item.position }
            value = max(value, child)
            localAlpha = max(localAlpha, value)
        }
        if state.options.useTranspositionTable {
            let bound: SearchBound = value <= alpha ? .upper : value >= beta ? .lower : .exact
            state.table[key] = SearchEntry(value: value, bound: bound, bestMove: bestMove)
        }
        return value
    }

    private static func assessedMoves(_ board: [CellState], _ size: Int, _ candidates: [Position], _ player: Player) -> [AssessedMove] {
        candidates.map { position in
            let attack = heuristic(board, size, position, player)
            let defense = heuristic(board, size, position, player.next)
            let center = Double(size) - hypot(Double(position.r - size / 2), Double(position.c - size / 2))
            return AssessedMove(position: position, attack: attack, defense: defense,
                                score: attack + defense * 0.92 + center,
                                ownWinningPoints: attack >= 24_000 ? winningContinuations(board, size, position, player) : [],
                                enemyWinningPoints: defense >= 24_000 ? winningContinuations(board, size, position, player.next) : [])
        }.sorted {
            $0.score == $1.score ? ($0.position.r, $0.position.c) < ($1.position.r, $1.position.c) : $0.score > $1.score
        }
    }

    private static func forkDefenses(_ board: inout [CellState], _ size: Int, _ moves: [AssessedMove], _ player: Player) -> [AssessedMove] {
        let forks = moves.filter { $0.enemyWinningPoints.count >= 2 }
        if forks.isEmpty { return moves }
        return moves.filter { defense in
            let index = defense.position.r * size + defense.position.c
            board[index] = player.cellState
            defer { board[index] = .empty }
            return forks.allSatisfy { fork in
                if fork.position == defense.position { return true }
                // A forcing counter-threat can win before the opponent's fork.
                if defense.ownWinningPoints.contains(where: { $0 != fork.position }) { return true }
                return winningContinuations(board, size, fork.position, player.next).count < 2
            }
        }
    }

    private static func winningContinuations(_ board: [CellState], _ size: Int, _ position: Position, _ player: Player) -> [Position] {
        var points: [Position] = []
        for (dr, dc) in directions {
            var values: [CellState] = []
            for offset in -4...4 {
                let r = position.r + dr * offset
                let c = position.c + dc * offset
                values.append(offset == 0 ? player.cellState : isInside(r, c, size) ? board[r * size + c] : player.next.cellState)
            }
            for start in 0...4 {
                var stones = 0
                var emptyOffset: Int?
                var emptyCount = 0
                for offset in start..<(start + 5) {
                    if values[offset] == player.cellState { stones += 1 }
                    if values[offset] == .empty { emptyCount += 1; emptyOffset = offset - 4 }
                }
                if stones == 4, emptyCount == 1, let offset = emptyOffset {
                    let point = Position(r: position.r + dr * offset, c: position.c + dc * offset)
                    if !points.contains(point) { points.append(point) }
                }
            }
        }
        return points
    }

    private static func evaluateMoves(_ moves: [AssessedMove]) -> Double {
        func strength(_ scores: [Double]) -> Double {
            let top = scores.sorted(by: >).prefix(3)
            return zip(top, [1.0, 0.18, 0.05]).reduce(0) { $0 + $1.0 * $1.1 }
        }
        // Side-to-move evaluation is antisymmetric; negamax supplies the sign.
        return strength(moves.map(\.attack)) - strength(moves.map(\.defense))
    }

    private static func candidatePositions(_ board: [CellState], _ size: Int) -> [Position] {
        var nearby = Array(repeating: false, count: board.count)
        var hasStones = false
        for index in board.indices where board[index] != .empty {
            hasStones = true
            let row = index / size
            let column = index % size
            for r in max(0, row - 2)...min(size - 1, row + 2) {
                for c in max(0, column - 2)...min(size - 1, column + 2) {
                    nearby[r * size + c] = true
                }
            }
        }
        guard hasStones else { return [Position(r: size / 2, c: size / 2)] }
        let candidates = board.indices.compactMap { index in
            nearby[index] && board[index] == .empty ? Position(r: index / size, c: index % size) : nil
        }
        return candidates.isEmpty ? emptyPositions(board, size) : candidates
    }

    private static func rankedCandidates(
        _ board: [CellState],
        _ size: Int,
        _ candidates: [Position],
        _ player: Player
    ) -> [RankedMove] {
        candidates.map { position in
            let attack = heuristic(board, size, position, player)
            let defense = heuristic(board, size, position, player.next)
            let center = Double(size) - hypot(Double(position.r - size / 2), Double(position.c - size / 2))
            return RankedMove(position: position, score: attack + defense * 0.92 + center)
        }
        .sorted {
            if $0.score == $1.score {
                return ($0.position.r, $0.position.c) < ($1.position.r, $1.position.c)
            }
            return $0.score > $1.score
        }
    }

    private static func heuristic(
        _ board: [CellState],
        _ size: Int,
        _ position: Position,
        _ player: Player
    ) -> Double {
        var total = 0.0
        for (dr, dc) in directions {
            let contiguous = lineStats(board, size, position, player, dr, dc)
            total += patternWeight(length: contiguous.length, openEnds: contiguous.openEnds)
            total += gappedThreat(board, size, position, player, dr, dc)
        }
        return total
    }

    private static func lineStats(
        _ board: [CellState],
        _ size: Int,
        _ position: Position,
        _ player: Player,
        _ dr: Int,
        _ dc: Int
    ) -> (length: Int, openEnds: Int) {
        var length = 1
        var openEnds = 0
        var r = position.r + dr
        var c = position.c + dc
        while isInside(r, c, size), board[r * size + c].player == player {
            length += 1
            r += dr
            c += dc
        }
        if isInside(r, c, size), board[r * size + c] == .empty { openEnds += 1 }

        r = position.r - dr
        c = position.c - dc
        while isInside(r, c, size), board[r * size + c].player == player {
            length += 1
            r -= dr
            c -= dc
        }
        if isInside(r, c, size), board[r * size + c] == .empty { openEnds += 1 }
        return (length, openEnds)
    }

    private static func gappedThreat(
        _ board: [CellState],
        _ size: Int,
        _ position: Position,
        _ player: Player,
        _ dr: Int,
        _ dc: Int
    ) -> Double {
        var values: [CellState] = []
        for offset in -4...4 {
            let r = position.r + dr * offset
            let c = position.c + dc * offset
            values.append(offset == 0 ? player.cellState : isInside(r, c, size) ? board[r * size + c] : player.next.cellState)
        }
        let target = player.cellState
        var score = 0.0
        var stones = 0
        var empties = 0
        for index in 0..<5 {
            if values[index] == target { stones += 1 }
            if values[index] == .empty { empties += 1 }
        }
        for start in 0...4 {
            if stones == 4 && empties == 1 { score += 32_000 }
            if stones == 3 && empties == 2 { score += 2_400 }
            if start < 4 {
                if values[start] == target { stones -= 1 }
                if values[start] == .empty { empties -= 1 }
                if values[start + 5] == target { stones += 1 }
                if values[start + 5] == .empty { empties += 1 }
            }
        }
        return score
    }

    private static func patternWeight(length: Int, openEnds: Int) -> Double {
        switch (length, openEnds) {
        case (5..., _): 1_000_000
        case (4, 2): 120_000
        case (4, 1): 24_000
        case (3, 2): 7_500
        case (3, 1): 1_300
        case (2, 2): 480
        case (2, 1): 90
        default: Double(length * 9 + openEnds * 4)
        }
    }

    private static func formsFive(
        _ board: [CellState],
        _ size: Int,
        _ position: Position,
        _ player: Player
    ) -> Bool {
        guard board[position.r * size + position.c] == .empty else { return false }
        return directions.contains { dr, dc in
            lineStats(board, size, position, player, dr, dc).length >= 5
        }
    }

    private static func emptyPositions(_ board: [CellState], _ size: Int) -> [Position] {
        board.indices.compactMap { index in
            board[index] == .empty ? Position(r: index / size, c: index % size) : nil
        }
    }

    private static func isInside(_ r: Int, _ c: Int, _ size: Int) -> Bool {
        (0..<size).contains(r) && (0..<size).contains(c)
    }

    private static func boardHash(_ board: [CellState]) -> UInt64 {
        board.reduce(1_469_598_103_934_665_603) { hash, cell in
            (hash ^ UInt64(cell.rawValue + 1)) &* 1_099_511_628_211
        }
    }

    private struct RankedMove {
        let position: Position
        let score: Double
    }

    private struct AssessedMove {
        let position: Position
        let attack: Double
        let defense: Double
        let score: Double
        let ownWinningPoints: [Position]
        let enemyWinningPoints: [Position]
    }

    private enum SearchBound { case exact, lower, upper }

    private struct SearchEntry {
        let value: Double
        let bound: SearchBound
        let bestMove: Position?
    }

    private struct SearchState {
        let deadline: ContinuousClock.Instant
        let options: SearchOptions
        var table: [SearchKey: SearchEntry] = [:]
        var visitedNodes = 0
        var interrupted = false

        mutating func canContinue() -> Bool {
            if Task.isCancelled || .now >= deadline { interrupted = true; return false }
            return true
        }
    }

    private struct SearchKey: Hashable {
        let hash: UInt64
        let player: Player
        let depth: Int
        let extensions: Int
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }
}
