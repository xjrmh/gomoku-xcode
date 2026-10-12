import Foundation

enum AIEngine {
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
        seed: UInt64 = 1
    ) -> Position? {
        guard board.count == size * size else { return nil }
        let empties = emptyPositions(board, size)
        guard !empties.isEmpty else { return nil }
        if empties.count == board.count {
            return Position(r: size / 2, c: size / 2)
        }

        let candidates = candidatePositions(board, size)
        let opponent = player.next

        if let win = candidates.first(where: { formsFive(board, size, $0, player) }) { return win }
        if let block = candidates.first(where: { formsFive(board, size, $0, opponent) }) { return block }

        switch difficulty {
        case .easy:
            var generator = SeededGenerator(seed: seed)
            let ranked = candidates
                .map { ($0, heuristic(board, size, $0, player) + heuristic(board, size, $0, opponent) * 0.65) }
                .sorted { $0.1 > $1.1 }
            let pool = Array(ranked.prefix(min(8, ranked.count)))
            guard let choice = pool.randomElement(using: &generator) else { return candidates.first }
            return choice.0

        case .medium:
            return rankedCandidates(board, size, candidates, player).first?.position

        case .hard:
            return hardMove(board: board, size: size, candidates: candidates, player: player, deadline: deadline)
        }
    }

    private static func hardMove(
        board: [CellState],
        size: Int,
        candidates: [Position],
        player: Player,
        deadline: ContinuousClock.Instant
    ) -> Position? {
        let ordered = Array(rankedCandidates(board, size, candidates, player).prefix(14))
        guard !ordered.isEmpty else { return candidates.first }

        var best = ordered[0].position
        var table: [SearchKey: Double] = [:]
        for depth in 1...4 {
            guard !Task.isCancelled, .now < deadline else { break }
            var completedDepth = true
            var depthBest = best
            var depthScore = -Double.infinity

            for item in ordered {
                guard !Task.isCancelled, .now < deadline else {
                    completedDepth = false
                    break
                }
                var next = board
                next[item.position.r * size + item.position.c] = player.cellState
                let score = -negamax(
                    board: next,
                    size: size,
                    player: player.next,
                    root: player,
                    depth: depth - 1,
                    alpha: -Double.infinity,
                    beta: .infinity,
                    deadline: deadline,
                    table: &table
                )
                if score > depthScore {
                    depthScore = score
                    depthBest = item.position
                }
            }
            if completedDepth { best = depthBest }
        }
        return best
    }

    private static func negamax(
        board: [CellState],
        size: Int,
        player: Player,
        root: Player,
        depth: Int,
        alpha: Double,
        beta: Double,
        deadline: ContinuousClock.Instant,
        table: inout [SearchKey: Double]
    ) -> Double {
        if Task.isCancelled || .now >= deadline { return evaluateBoard(board, size, root) }
        if depth == 0 { return evaluateBoard(board, size, root) * (player == root ? 1 : -1) }

        let key = SearchKey(hash: boardHash(board), player: player, depth: depth)
        if let cached = table[key] { return cached }

        let candidates = Array(rankedCandidates(board, size, candidatePositions(board, size), player).prefix(9))
        if candidates.isEmpty { return 0 }
        var localAlpha = alpha
        var value = -Double.infinity
        for item in candidates {
            if Task.isCancelled || .now >= deadline { break }
            if formsFive(board, size, item.position, player) { return 9_000_000 + Double(depth) }
            var next = board
            next[item.position.r * size + item.position.c] = player.cellState
            let child = -negamax(
                board: next,
                size: size,
                player: player.next,
                root: root,
                depth: depth - 1,
                alpha: -beta,
                beta: -localAlpha,
                deadline: deadline,
                table: &table
            )
            value = max(value, child)
            localAlpha = max(localAlpha, value)
            if localAlpha >= beta { break }
        }
        table[key] = value
        return value
    }

    private static func candidatePositions(_ board: [CellState], _ size: Int) -> [Position] {
        let occupied = occupiedPositions(board, size)
        guard !occupied.isEmpty else { return [Position(r: size / 2, c: size / 2)] }
        var candidates: [Position] = []
        candidates.reserveCapacity(size * 4)
        for position in emptyPositions(board, size) {
            if occupied.contains(where: {
                abs(position.r - $0.r) <= 2 && abs(position.c - $0.c) <= 2
            }) {
                candidates.append(position)
            }
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
        var simulated = board
        simulated[position.r * size + position.c] = player.cellState
        var total = 0.0
        for (dr, dc) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
            let contiguous = lineStats(simulated, size, position, player, dr, dc)
            total += patternWeight(length: contiguous.length, openEnds: contiguous.openEnds)
            total += gappedThreat(simulated, size, position, player, dr, dc)
        }
        return total
    }

    private static func evaluateBoard(_ board: [CellState], _ size: Int, _ player: Player) -> Double {
        var own = 0.0
        var opponent = 0.0
        for position in candidatePositions(board, size) {
            own = max(own, heuristic(board, size, position, player))
            opponent = max(opponent, heuristic(board, size, position, player.next))
        }
        return own - opponent * 1.05
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
            values.append(isInside(r, c, size) ? board[r * size + c] : player.next.cellState)
        }
        let target = player.cellState
        var score = 0.0
        for start in 0...4 {
            let window = values[start..<(start + 5)]
            let stones = window.filter { $0 == target }.count
            let empties = window.filter { $0 == .empty }.count
            if stones == 4 && empties == 1 { score += 32_000 }
            if stones == 3 && empties == 2 { score += 2_400 }
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
        var simulated = board
        simulated[position.r * size + position.c] = player.cellState
        return [(1, 0), (0, 1), (1, 1), (1, -1)].contains { dr, dc in
            lineStats(simulated, size, position, player, dr, dc).length >= 5
        }
    }

    private static func occupiedPositions(_ board: [CellState], _ size: Int) -> [Position] {
        board.indices.compactMap { index in
            board[index] == .empty ? nil : Position(r: index / size, c: index % size)
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

    private struct SearchKey: Hashable {
        let hash: UInt64
        let player: Player
        let depth: Int
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
