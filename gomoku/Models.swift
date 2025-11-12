//
//  Models.swift
//  gomoku
//
//  Created by Li Zheng on 11/11/25.
//

import SwiftUI
import Combine

enum GameMode: Hashable, CaseIterable { case pvp, ai }

enum CellState: Int {
    case empty = 0, black = 1, white = 2
    var player: Player? { self == .empty ? nil : (self == .black ? .black : .white) }
}

enum Player: Int {
    case black = 1
    case white = 2

    var next: Player { self == .black ? .white : .black }
    var stoneColor: Color { self == .black ? .black : .white }
    var name: String { self == .black ? "Black" : "White" }
}

struct Position: Hashable { let r: Int; let c: Int }
struct Move { let pos: Position; let player: Player }

final class GameState: ObservableObject {
    // Config
    @Published var boardSize: Int = 15
    @Published var theme: GomokuTheme = .classic
    @Published var mode: GameMode = .pvp {
        didSet {
            // If switching to AI mode while it's White's turn, prompt AI to move
            if mode == .ai, !gameOver, current == .white {
                scheduleAIMove()
            }
        }
    }

    // Game state
    @Published private(set) var board: [CellState]
    @Published private(set) var current: Player = .black
    @Published private(set) var moves: [Move] = []
    @Published private(set) var gameOver: Bool = false
    @Published private(set) var winner: Player? = nil
    @Published var hint: Position? = nil
    private var hintVersion: Int = 0
    @Published var showFireworks: Bool = false

    // Timers
    @Published var elapsedBlack: TimeInterval = 0
    @Published var elapsedWhite: TimeInterval = 0
    private var turnStart: Date = Date()
    private var clockStarted: Bool = false

    var statusText: String {
        if let w = winner { return "\(w.name) wins!" }
        switch mode {
        case .pvp: return "\(current.name)'s turn"
        case .ai:  return current == .black ? "Your move" : "AI thinking…"
        }
    }

    init() {
        self.board = Array(repeating: .empty, count: 15 * 15)
        self.turnStart = Date()
    }

    // Indexing
    func idx(_ r: Int, _ c: Int) -> Int { r * boardSize + c }
    func state(_ r: Int, _ c: Int) -> CellState {
        let i = idx(r, c)
        if i >= 0 && i < board.count {
            return board[i]
        } else {
            return .empty
        }
    }

    // Commands
    func reset(size: Int? = nil) {
        if let s = size { boardSize = s }
        board = Array(repeating: .empty, count: boardSize * boardSize)
        moves.removeAll()
        current = .black
        gameOver = false
        winner = nil
        hint = nil
        showFireworks = false
        elapsedBlack = 0
        elapsedWhite = 0
        clockStarted = false
        turnStart = Date()
    }

    func setMode(_ m: GameMode) {
        mode = m
        reset(size: boardSize)
    }

    func toggleTheme() { theme = (theme == .classic) ? .night : .classic }
    func sizePlus() { let ns = min(19, boardSize + 2); if ns != boardSize { reset(size: ns) } }
    func sizeMinus() { let ns = max(9, boardSize - 2); if ns != boardSize { reset(size: ns) } }

    func undo() {
        guard !moves.isEmpty, !showFireworks else { return }
        func popOne() {
            guard let last = moves.popLast() else { return }
            board[idx(last.pos.r, last.pos.c)] = .empty
            current = last.player
            winner = nil
            gameOver = false
        }
        if mode == .ai {
            popOne()
            if !moves.isEmpty { popOne() }
        } else {
            popOne()
        }
    }

    func playHuman(at pos: Position) {
        guard !gameOver, state(pos.r, pos.c) == .empty else { return }
        switch mode {
        case .pvp:
            place(at: pos, by: current)
            afterMove()
        case .ai:
            guard current == .black else { return }           // human is Black
            place(at: pos, by: .black)
            afterMove()
        }
    }

    private func place(at pos: Position, by player: Player) {
        board[idx(pos.r, pos.c)] = (player == .black ? .black : .white)
        moves.append(Move(pos: pos, player: player))
    }

    private func afterMove() {
        hint = nil
        if checkWin(from: moves.last!) {
            accumulateTimeForCurrent()
            gameOver = true
            winner = current
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, self.gameOver else { return }
                self.showFireworks = true
            }
            return
        }
        accumulateTimeForCurrent()
        current = current.next
        turnStart = Date()
        if mode == .ai, current == .white {
            scheduleAIMove()
        }
    }

    func scheduleAIMove() {
        guard !gameOver else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.aiMove() }
    }

    func aiMove() {
        guard mode == .ai, current == .white, !gameOver else { return }
        if let best = AIEngine.bestMove(for: .white, on: board, size: boardSize) {
            place(at: best, by: .white)
            if checkWin(from: moves.last!) {
                accumulateTimeForCurrent()
                gameOver = true
                winner = .white
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self = self, self.gameOver else { return }
                    self.showFireworks = true
                }
            } else {
                accumulateTimeForCurrent()
                current = .black
                turnStart = Date()
            }
        } else {
            // No move found; end the game as a draw and accumulate time for White
            accumulateTimeForCurrent()
            gameOver = true
            winner = nil
        }
    }

    func askForHint() {
        guard !gameOver else { return }
        let p = (mode == .ai && current == .white) ? Player.white : current
        hint = AIEngine.bestMove(for: p, on: board, size: boardSize)

        // Schedule auto-dismiss after 3 seconds; versioned to avoid clearing newer hints
        hintVersion &+= 1
        let version = hintVersion
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.hintVersion == version else { return }
            self.hint = nil
        }
    }

    // Timing helpers
    func elapsed(for player: Player, now: Date = Date()) -> TimeInterval {
        let base = (player == .black) ? elapsedBlack : elapsedWhite
        // Do not start counting until the first move has occurred
        guard clockStarted else { return base }
        if !gameOver, player == current {
            return base + now.timeIntervalSince(turnStart)
        } else {
            return base
        }
    }

    private func accumulateTimeForCurrent(now: Date = Date()) {
        // On the very first move, start the clock but do not count any pre-first-move time
        if !clockStarted {
            clockStarted = true
            turnStart = now
            return
        }
        if current == .black {
            elapsedBlack += now.timeIntervalSince(turnStart)
        } else {
            elapsedWhite += now.timeIntervalSince(turnStart)
        }
        turnStart = now
    }

    // Win detection
    @discardableResult
    func checkWin(from last: Move) -> Bool {
        let dirs = [(1,0), (0,1), (1,1), (1,-1)]
        for (dr, dc) in dirs {
            var count = 1
            count += countDirection(last.pos, dr, dc, last.player)
            count += countDirection(last.pos, -dr, -dc, last.player)
            if count >= 5 { return true }
        }
        return false
    }

    private func countDirection(_ start: Position, _ dr: Int, _ dc: Int, _ player: Player) -> Int {
        var r = start.r + dr, c = start.c + dc, cnt = 0
        while r >= 0, r < boardSize, c >= 0, c < boardSize, state(r, c).player == player {
            cnt += 1; r += dr; c += dc
        }
        return cnt
    }
}

