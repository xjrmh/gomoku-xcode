import SwiftUI

struct BoardCanvasView: View {
    @ObservedObject var game: GameState
    let palette: GomokuPalette
    var interactive = true

    @State private var gestureStart: Date?
    @State private var target: Position?
    @State private var precisionActive = false
    @State private var holdTask: Task<Void, Never>?
    @State private var cursor: Position = .init(r: 7, c: 7)
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2)
            ZStack {
                boardCanvas(side: side)
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                if precisionActive, let target {
                    loupe(for: target, boardSide: side)
                        .position(loupePosition(for: target, side: side, origin: origin, container: proxy.size))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(placementGesture(side: side, origin: origin), isEnabled: interactive)
            .focusable(interactive)
            .focused($keyboardFocused)
            .onKeyPress(.leftArrow) { moveCursor(dr: 0, dc: -1) }
            .onKeyPress(.rightArrow) { moveCursor(dr: 0, dc: 1) }
            .onKeyPress(.upArrow) { moveCursor(dr: -1, dc: 0) }
            .onKeyPress(.downArrow) { moveCursor(dr: 1, dc: 0) }
            .onKeyPress(.return) {
                game.playHuman(at: cursor)
                return .handled
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("game-board")
        .accessibilityLabel("Gomoku board, \(game.boardSize) by \(game.boardSize)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Use the named actions to move the board cursor and place a stone")
        .accessibilityAction(named: "Move left") { _ = moveCursor(dr: 0, dc: -1) }
        .accessibilityAction(named: "Move right") { _ = moveCursor(dr: 0, dc: 1) }
        .accessibilityAction(named: "Move up") { _ = moveCursor(dr: -1, dc: 0) }
        .accessibilityAction(named: "Move down") { _ = moveCursor(dr: 1, dc: 0) }
        .accessibilityAction(named: "Place stone") { game.playHuman(at: cursor) }
        .accessibilityAction(named: "Jump to last move") {
            if let last = game.moves.last?.pos { cursor = last }
        }
        .accessibilityAction(named: "Jump to hint") {
            if let hint = game.hint { cursor = hint }
        }
        .onAppear {
            let center = game.boardSize / 2
            cursor = Position(r: center, c: center)
        }
        .onDisappear { holdTask?.cancel() }
    }

    private func boardCanvas(side: CGFloat) -> some View {
        Canvas { context, size in
            BoardDrawing.draw(
                context: &context,
                size: size,
                board: game.board,
                boardSize: game.boardSize,
                lastMove: game.moves.last?.pos,
                winningLine: game.winningLine,
                hint: game.hint,
                preview: precisionActive ? target : nil,
                cursor: keyboardFocused ? cursor : nil,
                palette: palette
            )
        }
        .background(palette.boardWood, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.boardWood, lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }

    private func placementGesture(side: CGFloat, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let position = boardPosition(at: value.location, side: side, origin: origin)
                if gestureStart == nil {
                    gestureStart = .now
                    target = position
                    holdTask?.cancel()
                    holdTask = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.snappy(duration: 0.18)) { precisionActive = true }
                        }
                    }
                } else if position != target {
                    target = position
                    if precisionActive, position != nil { game.emitTargetChanged() }
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                let final = boardPosition(at: value.location, side: side, origin: origin) ?? target
                if let final { game.playHuman(at: final) }
                withAnimation(.easeOut(duration: 0.12)) { precisionActive = false }
                target = nil
                gestureStart = nil
            }
    }

    private func boardPosition(at point: CGPoint, side: CGFloat, origin: CGPoint) -> Position? {
        let localX = point.x - origin.x
        let localY = point.y - origin.y
        guard localX >= 0, localX < side, localY >= 0, localY < side else { return nil }
        let cell = side / CGFloat(game.boardSize)
        return Position(r: min(game.boardSize - 1, Int(localY / cell)), c: min(game.boardSize - 1, Int(localX / cell)))
    }

    private func loupePosition(for position: Position, side: CGFloat, origin: CGPoint, container: CGSize) -> CGPoint {
        let cell = side / CGFloat(game.boardSize)
        let x = origin.x + (CGFloat(position.c) + 0.5) * cell
        let targetY = origin.y + (CGFloat(position.r) + 0.5) * cell
        let above = targetY - 92
        return CGPoint(x: min(container.width - 74, max(74, x)), y: above < 74 ? targetY + 92 : above)
    }

    private func loupe(for position: Position, boardSide: CGFloat) -> some View {
        BoardLoupe(
            board: game.board,
            boardSize: game.boardSize,
            target: position,
            player: game.current,
            palette: palette
        )
        .frame(width: 136, height: 136)
        .transientClearGlass()
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @discardableResult
    private func moveCursor(dr: Int, dc: Int) -> KeyPress.Result {
        let r = min(game.boardSize - 1, max(0, cursor.r + dr))
        let c = min(game.boardSize - 1, max(0, cursor.c + dc))
        let next = Position(r: r, c: c)
        if next != cursor {
            cursor = next
            game.emitTargetChanged()
        }
        return .handled
    }

    private var accessibilityValue: String {
        let state = game.session.state(at: cursor)
        let occupant = state.player?.name ?? "empty"
        return "Cursor \(cursor.coordinate), \(occupant). \(game.statusText). \(game.moves.count) moves."
    }
}

struct BoardLoupe: View {
    let board: [CellState]
    let boardSize: Int
    let target: Position
    let player: Player
    let palette: GomokuPalette

    var body: some View {
        Canvas { context, size in
            let cell = size.width / 3
            for rowOffset in -1...1 {
                for columnOffset in -1...1 {
                    let r = target.r + rowOffset
                    let c = target.c + columnOffset
                    let rect = CGRect(
                        x: CGFloat(columnOffset + 1) * cell,
                        y: CGFloat(rowOffset + 1) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(Path(rect), with: .color((r + c).isMultiple(of: 2) ? palette.cellLight : palette.cellDark))
                    context.stroke(Path(rect), with: .color(palette.boardWood.opacity(0.75)), lineWidth: 1)
                    if (0..<boardSize).contains(r), (0..<boardSize).contains(c) {
                        let state = board[r * boardSize + c]
                        if state != .empty {
                            BoardDrawing.drawStone(context: &context, rect: rect.insetBy(dx: 6, dy: 6), player: state.player!, palette: palette)
                        }
                    }
                }
            }
            let targetRect = CGRect(x: cell, y: cell, width: cell, height: cell)
            if board[target.r * boardSize + target.c] == .empty {
                var ghost = context
                ghost.opacity = 0.7
                BoardDrawing.drawStone(context: &ghost, rect: targetRect.insetBy(dx: 6, dy: 6), player: player, palette: palette)
            }
            context.stroke(Path(ellipseIn: targetRect.insetBy(dx: 3, dy: 3)), with: .color(palette.winningGold), lineWidth: 3)
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
    }
}

enum BoardDrawing {
    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        board: [CellState],
        boardSize: Int,
        lastMove: Position?,
        winningLine: [Position],
        hint: Position?,
        preview: Position?,
        cursor: Position?,
        palette: GomokuPalette
    ) {
        guard boardSize > 0, board.count == boardSize * boardSize else { return }
        let cell = min(size.width, size.height) / CGFloat(boardSize)
        for r in 0..<boardSize {
            for c in 0..<boardSize {
                let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                context.fill(Path(rect), with: .color((r + c).isMultiple(of: 2) ? palette.cellLight : palette.cellDark))
                context.stroke(Path(rect), with: .color(palette.boardWood.opacity(0.72)), lineWidth: max(0.5, cell * 0.035))
                let state = board[r * boardSize + c]
                if let player = state.player {
                    drawStone(context: &context, rect: rect.insetBy(dx: max(1.5, cell * 0.14), dy: max(1.5, cell * 0.14)), player: player, palette: palette)
                }
            }
        }

        if winningLine.count >= 2 {
            let start = center(of: winningLine.first!, cell: cell)
            let end = center(of: winningLine.last!, cell: cell)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(palette.winningGold), style: StrokeStyle(lineWidth: max(3, cell * 0.12), lineCap: .round))
            for position in winningLine {
                let rect = cellRect(position, cell: cell).insetBy(dx: max(1, cell * 0.08), dy: max(1, cell * 0.08))
                context.stroke(Path(ellipseIn: rect), with: .color(palette.winningGold), lineWidth: max(2, cell * 0.09))
            }
        }

        if let lastMove {
            let rect = cellRect(lastMove, cell: cell)
            let dot = rect.insetBy(dx: cell * 0.42, dy: cell * 0.42)
            let color: Color = board[lastMove.r * boardSize + lastMove.c] == .black ? .white : .black
            context.fill(Path(ellipseIn: dot), with: .color(color))
        }

        if let hint, board[hint.r * boardSize + hint.c] == .empty {
            context.stroke(Path(ellipseIn: cellRect(hint, cell: cell).insetBy(dx: cell * 0.2, dy: cell * 0.2)), with: .color(.red), lineWidth: max(2, cell * 0.07))
        }

        if let preview, board[preview.r * boardSize + preview.c] == .empty {
            var ghost = context
            ghost.opacity = 0.55
            drawStone(context: &ghost, rect: cellRect(preview, cell: cell).insetBy(dx: max(1.5, cell * 0.14), dy: max(1.5, cell * 0.14)), player: board.compactMap(\.player).count.isMultiple(of: 2) ? .black : .white, palette: palette)
        }

        if let cursor {
            context.stroke(Path(cellRect(cursor, cell: cell).insetBy(dx: 1, dy: 1)), with: .color(.blue), lineWidth: max(2, cell * 0.08))
        }
    }

    static func drawStone(context: inout GraphicsContext, rect: CGRect, player: Player, palette: GomokuPalette) {
        let color: Color = player == .black ? .black : .white
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.stroke(Path(ellipseIn: rect), with: .color(player == .white ? palette.stoneBorder : .black.opacity(0.45)), lineWidth: 1)
    }

    private static func cellRect(_ position: Position, cell: CGFloat) -> CGRect {
        CGRect(x: CGFloat(position.c) * cell, y: CGFloat(position.r) * cell, width: cell, height: cell)
    }

    private static func center(of position: Position, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(position.c) + 0.5) * cell, y: (CGFloat(position.r) + 0.5) * cell)
    }
}

struct StaticBoardView: View {
    let board: [CellState]
    let boardSize: Int
    let lastMove: Position?
    let winningLine: [Position]
    let palette: GomokuPalette

    var body: some View {
        Canvas { context, size in
            BoardDrawing.draw(
                context: &context,
                size: size,
                board: board,
                boardSize: boardSize,
                lastMove: lastMove,
                winningLine: winningLine,
                hint: nil,
                preview: nil,
                cursor: nil,
                palette: palette
            )
        }
        .background(palette.boardWood)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.boardWood, lineWidth: 1))
        .aspectRatio(1, contentMode: .fit)
    }
}
