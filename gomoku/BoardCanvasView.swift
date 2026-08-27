import SwiftUI

private struct BoardGeometry {
    let side: CGFloat
    let boardSize: Int
    let inset: CGFloat
    let step: CGFloat
    let stoneDiameter: CGFloat

    init(side: CGFloat, boardSize: Int) {
        self.side = side
        self.boardSize = boardSize
        step = side / CGFloat(max(1, boardSize))
        inset = step / 2
        stoneDiameter = min(step * 0.78, step - 2)
    }

    func point(for position: Position) -> CGPoint {
        CGPoint(
            x: inset + CGFloat(position.c) * step,
            y: inset + CGFloat(position.r) * step
        )
    }

    func stoneRect(for position: Position) -> CGRect {
        let center = point(for: position)
        return CGRect(
            x: center.x - stoneDiameter / 2,
            y: center.y - stoneDiameter / 2,
            width: stoneDiameter,
            height: stoneDiameter
        )
    }

    func position(at point: CGPoint) -> Position? {
        guard point.x >= 0, point.x <= side, point.y >= 0, point.y <= side else { return nil }
        let column = Int(((point.x - inset) / step).rounded())
        let row = Int(((point.y - inset) / step).rounded())
        guard (0..<boardSize).contains(row), (0..<boardSize).contains(column) else { return nil }
        return Position(r: row, c: column)
    }
}

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
        .background(palette.boardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.boardEdge.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 9, y: 4)
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
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        return BoardGeometry(side: side, boardSize: game.boardSize).position(at: local)
    }

    private func loupePosition(for position: Position, side: CGFloat, origin: CGPoint, container: CGSize) -> CGPoint {
        let point = BoardGeometry(side: side, boardSize: game.boardSize).point(for: position)
        let x = origin.x + point.x
        let targetY = origin.y + point.y
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
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.boardSurface))

            var grid = Path()
            for index in 0..<3 {
                let coordinate = (CGFloat(index) + 0.5) * cell
                grid.move(to: CGPoint(x: coordinate, y: 0))
                grid.addLine(to: CGPoint(x: coordinate, y: size.height))
                grid.move(to: CGPoint(x: 0, y: coordinate))
                grid.addLine(to: CGPoint(x: size.width, y: coordinate))
            }
            context.stroke(grid, with: .color(palette.boardGrid.opacity(0.78)), lineWidth: 1)

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
                    if (0..<boardSize).contains(r), (0..<boardSize).contains(c) {
                        let state = board[r * boardSize + c]
                        if state != .empty {
                            BoardDrawing.drawStone(
                                context: &context,
                                rect: rect.insetBy(dx: cell * 0.15, dy: cell * 0.15),
                                player: state.player!,
                                palette: palette
                            )
                        }
                    }
                }
            }
            let targetRect = CGRect(x: cell, y: cell, width: cell, height: cell)
            if board[target.r * boardSize + target.c] == .empty {
                var ghost = context
                ghost.opacity = 0.7
                BoardDrawing.drawStone(
                    context: &ghost,
                    rect: targetRect.insetBy(dx: cell * 0.15, dy: cell * 0.15),
                    player: player,
                    palette: palette
                )
            }
            context.stroke(
                Path(ellipseIn: targetRect.insetBy(dx: 3, dy: 3)),
                with: .color(palette.winningGold),
                lineWidth: 3
            )
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
        let side = min(size.width, size.height)
        let geometry = BoardGeometry(side: side, boardSize: boardSize)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.boardSurface))

        var grid = Path()
        let start = geometry.inset
        let end = side - geometry.inset
        for index in 0..<boardSize {
            let coordinate = geometry.inset + CGFloat(index) * geometry.step
            grid.move(to: CGPoint(x: coordinate, y: start))
            grid.addLine(to: CGPoint(x: coordinate, y: end))
            grid.move(to: CGPoint(x: start, y: coordinate))
            grid.addLine(to: CGPoint(x: end, y: coordinate))
        }
        context.stroke(
            grid,
            with: .color(palette.boardGrid.opacity(0.82)),
            lineWidth: max(0.7, geometry.step * 0.032)
        )

        for position in starPoints(for: boardSize) {
            let center = geometry.point(for: position)
            let radius = max(2, geometry.step * 0.09)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(palette.boardGrid))
        }

        for r in 0..<boardSize {
            for c in 0..<boardSize {
                let state = board[r * boardSize + c]
                if let player = state.player {
                    drawStone(
                        context: &context,
                        rect: geometry.stoneRect(for: Position(r: r, c: c)),
                        player: player,
                        palette: palette
                    )
                }
            }
        }

        if winningLine.count >= 2 {
            let start = geometry.point(for: winningLine.first!)
            let end = geometry.point(for: winningLine.last!)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(
                path,
                with: .color(palette.winningGold),
                style: StrokeStyle(lineWidth: max(3, geometry.step * 0.12), lineCap: .round)
            )
            for position in winningLine {
                let rect = geometry.stoneRect(for: position).insetBy(dx: -2, dy: -2)
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(palette.winningGold),
                    lineWidth: max(2, geometry.step * 0.09)
                )
            }
        }

        if let lastMove {
            let stoneRect = geometry.stoneRect(for: lastMove)
            let ring = stoneRect.insetBy(dx: stoneRect.width * 0.3, dy: stoneRect.height * 0.3)
            let color: Color = board[lastMove.r * boardSize + lastMove.c] == .black ? .white : .black
            context.stroke(
                Path(ellipseIn: ring),
                with: .color(color.opacity(0.92)),
                lineWidth: max(1.5, geometry.step * 0.075)
            )
        }

        if let hint, board[hint.r * boardSize + hint.c] == .empty {
            let rect = geometry.stoneRect(for: hint).insetBy(dx: 1, dy: 1)
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(palette.winningGold),
                style: StrokeStyle(lineWidth: max(2, geometry.step * 0.075), dash: [4, 3])
            )
        }

        if let preview, board[preview.r * boardSize + preview.c] == .empty {
            var ghost = context
            ghost.opacity = 0.55
            drawStone(
                context: &ghost,
                rect: geometry.stoneRect(for: preview),
                player: board.compactMap(\.player).count.isMultiple(of: 2) ? .black : .white,
                palette: palette
            )
        }

        if let cursor {
            let rect = geometry.stoneRect(for: cursor).insetBy(dx: -3, dy: -3)
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(.blue),
                lineWidth: max(2, geometry.step * 0.08)
            )
        }
    }

    static func drawStone(context: inout GraphicsContext, rect: CGRect, player: Player, palette: GomokuPalette) {
        let path = Path(ellipseIn: rect)
        let gradient = player == .black
            ? Gradient(stops: [
                .init(color: Color(white: 0.34), location: 0),
                .init(color: Color(white: 0.09), location: 0.55),
                .init(color: Color(white: 0.025), location: 1),
            ])
            : Gradient(stops: [
                .init(color: .white, location: 0),
                .init(color: Color(white: 0.92), location: 0.62),
                .init(color: Color(white: 0.79), location: 1),
            ])

        context.drawLayer { layer in
            layer.addFilter(.shadow(
                color: .black.opacity(player == .black ? 0.3 : 0.2),
                radius: max(1.25, rect.width * 0.1),
                x: 0,
                y: max(1, rect.height * 0.08)
            ))
            layer.fill(
                path,
                with: .radialGradient(
                    gradient,
                    center: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.28),
                    startRadius: 0,
                    endRadius: rect.width * 0.78
                )
            )
        }

        context.stroke(
            path,
            with: .color(player == .white ? palette.stoneBorder : .black.opacity(0.62)),
            lineWidth: max(0.75, rect.width * 0.035)
        )

    }

    private static func starPoints(for boardSize: Int) -> [Position] {
        guard boardSize >= 7 else {
            let center = boardSize / 2
            return [Position(r: center, c: center)]
        }
        if boardSize < 13 {
            let edge = 2
            let farEdge = boardSize - edge - 1
            let center = boardSize / 2
            return [
                Position(r: edge, c: edge),
                Position(r: edge, c: farEdge),
                Position(r: center, c: center),
                Position(r: farEdge, c: edge),
                Position(r: farEdge, c: farEdge),
            ]
        }
        let coordinates = [3, boardSize / 2, boardSize - 4]
        return coordinates.flatMap { row in coordinates.map { Position(r: row, c: $0) } }
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
        .background(palette.boardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(palette.boardEdge, lineWidth: 1))
        .aspectRatio(1, contentMode: .fit)
    }
}
