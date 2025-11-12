//
//  AIEngine.swift
//  gomoku
//
//  Created by Li Zheng on 11/11/25.
//

import Foundation

enum AIEngine {
    static func bestMove(for player: Player, on board: [CellState], size: Int) -> Position? {
        let opp: Player = player == .black ? .white : .black

        let occupied = allOccupied(board, size)
        let empties = allEmpties(board, size)

        if occupied.isEmpty {
            let c = size / 2
            return Position(r: c, c: c)
        }

        let candidates = empties.filter { isNearAny($0, occupied, distance: 2) }
        if candidates.isEmpty { return empties.randomElement() }

        for pos in candidates { if formsFive(board, size, pos, player) { return pos } }
        for pos in candidates { if formsFive(board, size, pos, opp)    { return pos } }

        var best: Position? = nil
        var bestScore = Double.leastNonzeroMagnitude
        for pos in candidates {
            let sSelf = scoreSim(board, size, pos, player)
            let sOpp  = scoreSim(board, size, pos, opp)
            let score = sSelf * 1.0 + sOpp * 0.9
            if score > bestScore { bestScore = score; best = pos }
        }
        return best ?? candidates.first
    }

    private static func allOccupied(_ board: [CellState], _ size: Int) -> [Position] {
        var out: [Position] = []
        out.reserveCapacity(size * size / 4)
        for r in 0..<size {
            for c in 0..<size where board[r*size + c] != .empty {
                out.append(Position(r: r, c: c))
            }
        }
        return out
    }

    private static func allEmpties(_ board: [CellState], _ size: Int) -> [Position] {
        var out: [Position] = []
        out.reserveCapacity(size * size)
        for r in 0..<size {
            for c in 0..<size where board[r*size + c] == .empty {
                out.append(Position(r: r, c: c))
            }
        }
        return out
    }

    private static func isNearAny(_ p: Position, _ pts: [Position], distance: Int) -> Bool {
        for q in pts { if abs(p.r - q.r) <= distance && abs(p.c - q.c) <= distance { return true } }
        return false
    }

    private static func formsFive(_ board: [CellState], _ size: Int, _ pos: Position, _ player: Player) -> Bool {
        var b = board
        b[pos.r*size + pos.c] = (player == .black ? .black : .white)
        let move = Move(pos: pos, player: player)
        return checkWin(b, size, move)
    }

    private static func checkWin(_ b: [CellState], _ size: Int, _ last: Move) -> Bool {
        func st(_ r: Int,_ c: Int) -> CellState { b[r*size + c] }
        let dirs = [(1,0),(0,1),(1,1),(1,-1)]
        for (dr, dc) in dirs {
            var count = 1
            var r = last.pos.r + dr, c = last.pos.c + dc
            while r >= 0, r < size, c >= 0, c < size, st(r,c).player == last.player { count += 1; r += dr; c += dc }
            r = last.pos.r - dr; c = last.pos.c - dc
            while r >= 0, r < size, c >= 0, c < size, st(r,c).player == last.player { count += 1; r -= dr; c -= dc }
            if count >= 5 { return true }
        }
        return false
    }

    private static func scoreSim(_ board: [CellState], _ size: Int, _ pos: Position, _ player: Player) -> Double {
        var b = board
        b[pos.r*size + pos.c] = (player == .black ? .black : .white)
        let lines: [(Int,Int)] = [(1,0),(0,1),(1,1),(1,-1)]
        var total = 0.0
        for (dr, dc) in lines {
            let (len, openEnds) = lineStats(b, size, pos, player, dr, dc)
            total += weight(len: len, openEnds: openEnds)
        }
        return total
    }

    private static func lineStats(_ b: [CellState], _ size: Int, _ pos: Position, _ player: Player, _ dr: Int, _ dc: Int) -> (len: Int, openEnds: Int) {
        func st(_ r: Int,_ c: Int) -> CellState { b[r*size + c] }
        var len = 1, open = 0

        var r = pos.r + dr, c = pos.c + dc
        while r >= 0, r < size, c >= 0, c < size, st(r,c).player == player { len += 1; r += dr; c += dc }
        if r >= 0, r < size, c >= 0, c < size, st(r,c) == .empty { open += 1 }

        r = pos.r - dr; c = pos.c - dc
        while r >= 0, r < size, c >= 0, c < size, st(r,c).player == player { len += 1; r -= dr; c -= dc }
        if r >= 0, r < size, c >= 0, c < size, st(r,c) == .empty { open += 1 }

        return (len, open)
    }

    private static func weight(len: Int, openEnds: Int) -> Double {
        switch (len, openEnds) {
        case (5, _): return 1_000_000
        case (4, 2): return 100_000
        case (4, 1): return 20_000
        case (3, 2): return 6_000
        case (3, 1): return 1_200
        case (2, 2): return 400
        case (2, 1): return 80
        default: return Double(len * 8 + openEnds * 3)
        }
    }
}
