//
//  ContentView.swift
//  gomoku
//
//  Created by Li Zheng on 11/11/25.
//

import SwiftUI
import Combine

private struct BoardFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct ContentView: View {
    @StateObject private var game = GameState()
    @State private var showAbout: Bool = false
    @State private var boardFrame: CGRect = .zero
    @State private var showRestartConfirm1: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    game.theme.chrome.ignoresSafeArea()

                    VStack(spacing: 10) {
                        BoardView()
                            .environmentObject(game)
                            .background(
                                GeometryReader { g in
                                    Color.clear
                                        .preference(key: BoardFramePreferenceKey.self, value: g.frame(in: .global))
                                }
                            )
                            .padding(.horizontal, 2)
                            .padding(.bottom, 12)

                        StatsBar()
                            .environmentObject(game)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onPreferenceChange(BoardFramePreferenceKey.self) { frame in
                        self.boardFrame = frame
                    }
                    .overlay(alignment: .center) {
                        if let win = game.winner, game.gameOver {
                            VStack(spacing: 12) {
                                VictoryMessage(text: "\(win.name) Wins!", player: win)
                                TapToPlayAgainHint()
                                    .transition(.opacity)
                                    .animation(.easeInOut(duration: 0.3), value: game.gameOver)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        if game.showFireworks, let last = game.moves.last, boardFrame != .zero {
                            let fx = (CGFloat(last.pos.c) + 0.5) / CGFloat(game.boardSize)
                            let fy = (CGFloat(last.pos.r) + 0.5) / CGFloat(game.boardSize)
                            let startGlobal = CGPoint(x: boardFrame.minX + boardFrame.width * fx,
                                                      y: boardFrame.minY + boardFrame.height * fy)
                            EmojiFireworksOverlay(isActive: $game.showFireworks, startPointGlobal: startGlobal)
                                .ignoresSafeArea()
                        }
                    }
                    .overlay {
                        if showRestartConfirm1 {
                            Color.clear
                                .contentShape(Rectangle())
                                .ignoresSafeArea()
                                .onTapGesture {
                                    showRestartConfirm1 = false
                                }
                        }
                    }
                    #if os(macOS)
                    .overlay(alignment: .topTrailing) {
                        if showRestartConfirm1 {
                            VStack(spacing: 8) {
                                HStack(spacing: 12) {
                                    Button("Restart", role: .destructive) {
                                        game.reset(size: game.boardSize)
                                        showRestartConfirm1 = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
                            .padding(.top, -43)
                            .padding(.trailing, 50)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showRestartConfirm1)
                        }
                    }
                    #else
                    .overlay(alignment: .bottomLeading) {
                        if showRestartConfirm1 {
                            VStack(spacing: 8) {
                                HStack(spacing: 12) {
                                    Button("Restart", role: .destructive) {
                                        game.reset(size: game.boardSize)
                                        showRestartConfirm1 = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
                            .padding(.bottom, 4)
                            .padding(.leading, 80)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showRestartConfirm1)
                        }
                    }
                    #endif
                    .overlay(alignment: .bottom) {
                        if game.gameOver, game.winner == nil {
                            TapToPlayAgainHint()
                                .padding(.bottom, 24)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.3), value: game.gameOver)
                        }
                    }
                    .overlay {
                        if game.gameOver {
                            Color.clear
                                .contentShape(Rectangle())
                                .ignoresSafeArea()
                                .onTapGesture {
                                    game.showFireworks = false
                                    game.reset(size: game.boardSize)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Gomoku")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack(alignment: .top) {
                    if !game.gameOver {
                        StatusChip(text: game.statusText, player: game.current, theme: game.theme)
                            .padding(.top, 4)
                    }
                }
                .frame(height: 44, alignment: .top)
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $game.mode) {
                        Text("PvP Mode").tag(GameMode.pvp)
                        Text("AI Mode").tag(GameMode.ai)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            game.toggleTheme()
                        } label: {
                            Label("Dark Mode", systemImage: "paintbrush")
                        }
                        Divider()
                        Button {
                            game.reset(size: 15)
                        } label: {
                            Label("15×15 Board", systemImage: "checkerboard.rectangle")
                        }
                        .disabled(game.boardSize == 15)
                        Button {
                            game.reset(size: 19)
                        } label: {
                            Label("19×19 Board", systemImage: "checkerboard.rectangle")
                        }
                        .disabled(game.boardSize == 19)
                        Button {
                            game.sizePlus()
                        } label: {
                            Label("Larger Board", systemImage: "plus.circle")
                        }
                        Button {
                            game.sizeMinus()
                        } label: {
                            Label("Smaller Board", systemImage: "minus.circle")
                        }
                        Divider()
                        Button {
                            game.reset(size: 15)
                        } label: {
                            Label("Reset to Default", systemImage: "arrow.clockwise")
                        }
                        Button {
                            showAbout = true
                        } label: {
                            Label("About", systemImage: "info.circle")
                        }
                    } label: {
                        Label("Options", systemImage: "gearshape")
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showRestartConfirm1 = true
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button {
                        game.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }

                    Button {
                        game.askForHint()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker("Mode", selection: $game.mode) {
                        Text("PvP Mode").tag(GameMode.pvp)
                        Text("AI Mode").tag(GameMode.ai)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }

                ToolbarItemGroup(placement: .automatic) {
                    Menu {
                        Button {
                            game.toggleTheme()
                        } label: {
                            Label("Dark Mode", systemImage: "paintbrush")
                        }
                        
                        Divider()
                        Button {
                            game.reset(size: 15)
                        } label: {
                            Label("15×15 Board", systemImage: "checkerboard.rectangle")
                        }
                        .disabled(game.boardSize == 15)
                        Button {
                            game.reset(size: 19)
                        } label: {
                            Label("19×19 Board", systemImage: "checkerboard.rectangle")
                        }
                        .disabled(game.boardSize == 19)
                        Button {
                            game.sizePlus()
                        } label: {
                            Label("Increase", systemImage: "plus.circle")
                        }
                        Button {
                            game.sizeMinus()
                        } label: {
                            Label("Decrease", systemImage: "minus.circle")
                        }

                        Divider()
                        Button {
                            game.reset(size: 15)
                        } label: {
                            Label("Reset to Default", systemImage: "arrow.clockwise")
                        }
                        Button {
                            showAbout = true
                        } label: {
                            Label("About", systemImage: "info.circle")
                        }
                    } label: {
                        Label("Options", systemImage: "gearshape")
                    }
                }

                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        showRestartConfirm1 = true
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        game.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }

                    Button {
                        game.askForHint()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }
            }
            #endif
            .coordinateSpace(name: "root")
            #if os(macOS)
            .popover(isPresented: $showAbout) {
                AboutView(theme: game.theme)
            }
            #else
            .sheet(isPresented: $showAbout) {
                AboutView(theme: game.theme)
            }
            #endif
            .onAppear {
                let desired: GomokuTheme = (colorScheme == .dark) ? .night : .classic
                if game.theme != desired { game.theme = desired }
            }
            .onChange(of: colorScheme) { _, _ in
                let desired: GomokuTheme = (colorScheme == .dark) ? .night : .classic
                if game.theme != desired { game.theme = desired }
            }
        }
    }
}

struct BoardView: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.97
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(game.theme.boardWood)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: game.boardSize), spacing: 1) {
                    ForEach(0..<(game.boardSize * game.boardSize), id: \.self) { idx in
                        let r = idx / game.boardSize
                        let c = idx % game.boardSize
                        CellView(r: r, c: c)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .padding(2)
            }
            .frame(width: side, height: side)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CellView: View {
    @EnvironmentObject var game: GameState
    let r: Int
    let c: Int

    var body: some View {
        let cell = game.state(r, c)
        ZStack {
            Rectangle()
                .fill(((r + c) % 2 == 0) ? game.theme.cellLight : game.theme.cellDark)

            if cell != .empty {
                Circle()
                    .fill(cell == .black ? Color.black : Color.white)
                    .overlay(Circle().stroke(game.theme.stoneBorder, lineWidth: cell == .white ? 1 : 0))
                    .padding(4)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 2)
            }

            if let hint = game.hint, hint.r == r, hint.c == c, game.state(r, c) == .empty {
                HintIndicator(color: .red)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { game.playHuman(at: Position(r: r, c: c)) }
    }
}

struct VictoryMessage: View {
    let text: String
    let player: Player

    var body: some View {
        Text(text)
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .foregroundStyle(player == .black ? Color.black : Color.white)
            .shadow(color: .black.opacity(0.85), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 12)
    }
}

struct TapToPlayAgainHint: View {
    var body: some View {
        Label {
            Text("Tap to play again")
                .font(.footnote.weight(.semibold))
        } icon: {
            Image(systemName: "hand.tap")
                .font(.footnote)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)
        .opacity(0.92)
    }
}

struct StatusChip: View {
    let text: String
    let player: Player
    let theme: GomokuTheme

    var body: some View {
        Label {
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.text)
        } icon: {
            Circle()
                .fill(player == .black ? Color.black : Color.white)
                .overlay(Circle().stroke(theme.stoneBorder, lineWidth: player == .white ? 1 : 0))
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: text)
    }
}

struct StatsBar: View {
    @EnvironmentObject var game: GameState
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            // Black timer
            Label {
                Text(timeString(game.elapsed(for: .black, now: now)))
                    .font(.caption.monospacedDigit().weight(.semibold))
            } icon: {
                Circle().fill(Color.black)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(game.theme.stoneBorder, lineWidth: 0))
            }

            Divider()
                .frame(height: 14)
                .overlay(Color.primary.opacity(0.15))

            // Move count
            Label {
                Text("Moves: \(game.moves.count)")
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: "number")
                    .font(.caption)
            }

            Divider()
                .frame(height: 14)
                .overlay(Color.primary.opacity(0.15))

            // White timer
            Label {
                Text(timeString(game.elapsed(for: .white, now: now)))
                    .font(.caption.monospacedDigit().weight(.semibold))
            } icon: {
                Circle().fill(Color.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(game.theme.stoneBorder, lineWidth: 1))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        .onReceive(timer) { date in
            now = date
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
}

struct HintIndicator: View {
    @State private var pulse = false
    @State private var rotate = false
    let color: Color

    var body: some View {
        ZStack {
            // Outer halo
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 10)
                .scaleEffect(pulse ? 1.8 : 1.2)
                .opacity(pulse ? 0.0 : 0.35)
                .blur(radius: 1.5)
                .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)

            // Expanding ripple
            Circle()
                .stroke(color.opacity(0.6), lineWidth: 8)
                .scaleEffect(pulse ? 1.6 : 0.7)
                .opacity(pulse ? 0.0 : 0.8)
                .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)

            // Soft glow fill
            Circle()
                .fill(color.opacity(0.22))
                .blur(radius: 2)

            // Rotating dashed ring
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 3, dash: [5, 3]))
                .foregroundStyle(color.opacity(0.6))
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(.linear(duration: 1.8).repeatForever(autoreverses: false), value: rotate)

            // Core ring
            Circle()
                .stroke(color.opacity(1.0), lineWidth: 3)
                .scaleEffect(pulse ? 1.12 : 0.9)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        }
        .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 1)
        .onAppear {
            pulse = true
            rotate = true
        }
    }
}

struct AboutView: View {
    let theme: GomokuTheme
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
                .padding(.top, 8)

            Text("Created by Li Zheng (li_zheng@outlook.com). Of course it's AI assisted.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .presentationDetents([.height(160)])
    }
}

