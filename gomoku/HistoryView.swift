import SwiftData
import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pvp = "PvP"
    case ai = "AI"

    var id: Self { self }
    var title: String { self == .pvp ? "2 Players" : rawValue }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \ArchivedGame.completedAt, order: .reverse) private var games: [ArchivedGame]
    @State private var filter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var showEraseConfirmation = false

    private var palette: GomokuPalette { .resolve(colorScheme) }
    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(maximum: 440))]
            : [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)]
    }
    private var filteredGames: [ArchivedGame] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "×", with: "x")
        return games.filter { game in
            let matchesMode = switch filter {
            case .all: true
            case .pvp: game.modes.contains(.pvp)
            case .ai: game.modes.contains(.ai)
            }
            guard matchesMode else { return false }
            guard !query.isEmpty else { return true }
            let searchable = [
                game.resultTitle,
                game.finalMode.title,
                game.finalMode == .pvp ? "2 Players PvP" : "AI",
                game.difficulty.title,
                "\(game.boardSize)x\(game.boardSize)",
                game.completedAt.formatted(date: .abbreviated, time: .omitted)
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            modePicker
                .padding(.horizontal)
                .padding(.top, 8)

            if filteredGames.isEmpty {
                ContentUnavailableView(
                    games.isEmpty ? "No Games Yet" : "No Matches",
                    systemImage: games.isEmpty ? "square.grid.2x2" : "magnifyingglass",
                    description: Text(games.isEmpty ? "Completed games will appear here." : "Try another search or choose a different game type.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    ForEach(filteredGames) { game in
                        NavigationLink {
                            ReplayView(game: game)
                        } label: {
                            HistoryCard(game: game, palette: palette)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("history-game-card")
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(game)
                                try? modelContext.save()
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Result, mode, size, or date")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu("History options", systemImage: "ellipsis.circle") {
                    Button("Erase All History", systemImage: "trash", role: .destructive) {
                        showEraseConfirmation = true
                    }
                    .disabled(games.isEmpty)
                }
            }
        }
        .confirmationDialog(
            "Erase all game history?",
            isPresented: $showEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase All History", role: .destructive) { ArchiveRepository.eraseAll(in: modelContext) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the synced archive from all of your devices and can’t be undone.")
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Picker("Game type", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Game type", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }
                .pickerStyle(.segmented)
            }
        }
        .accessibilityIdentifier("history-game-filter")
    }
}

private struct HistoryCard: View {
    let game: ArchivedGame
    let palette: GomokuPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StaticBoardView(
                board: game.finalBoard,
                boardSize: game.boardSize,
                lastMove: game.moves.last?.pos,
                winningLine: game.winningLine,
                palette: palette
            )
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StoneDot(player: game.winner)
                Text(game.resultTitle)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            Text(game.completedAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(metadata) · \(game.moveCount) moves")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens move-by-move replay")
    }

    private var metadata: String {
        var parts = [game.finalMode == .pvp ? "2 Players" : game.finalMode.title]
        if game.finalMode == .ai { parts.append(game.difficulty.title) }
        parts.append("\(game.boardSize)×\(game.boardSize)")
        return parts.joined(separator: " · ")
    }
}

struct ReplayView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let game: ArchivedGame
    @State private var moveIndex: Int
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?

    init(game: ArchivedGame) {
        self.game = game
        _moveIndex = State(initialValue: game.moves.count)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if geometry.size.width >= 800,
                       geometry.size.width > geometry.size.height,
                       !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .center, spacing: 24) {
                            replayBoard
                                .frame(width: min(760, min(max(240, geometry.size.height - 32), geometry.size.width * 0.6)))
                            playbackControls
                                .frame(maxWidth: 360)
                        }
                    } else {
                        VStack(spacing: 20) {
                            replayBoard
                                .frame(maxWidth: 760)
                            playbackControls
                                .frame(maxWidth: 620)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 32))
                .padding(16)
            }
        }
        .navigationTitle(game.resultTitle)
        .onDisappear { stopPlayback() }
    }

    private var selectedMove: MoveRecord? {
        let moves = game.moves
        guard moves.indices.contains(moveIndex - 1) else { return nil }
        return moves[moveIndex - 1]
    }

    private var selectedMoveSummary: String {
        guard let selectedMove else { return "Starting position" }
        let player = selectedMove.controller == .ai ? "\(selectedMove.player.name) (AI)" : selectedMove.player.name
        return "\(player) at \(selectedMove.pos.coordinate)"
    }

    private var replayPositionDescription: String {
        "Move \(moveIndex) of \(game.moves.count). \(selectedMoveSummary)"
    }

    private var replayBoard: some View {
        StaticBoardView(
            board: game.board(after: moveIndex),
            boardSize: game.boardSize,
            lastMove: selectedMove?.pos,
            winningLine: moveIndex == game.moves.count ? game.winningLine : [],
            palette: .resolve(colorScheme)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Replay board, \(game.boardSize) by \(game.boardSize)")
        .accessibilityValue(boardSummary)
    }

    private var boardSummary: String {
        let moves = game.moves.prefix(moveIndex)
        let blackCount = moves.filter { $0.player == .black }.count
        let whiteCount = moves.count - blackCount
        let result = moveIndex == game.moves.count ? " \(game.resultTitle)." : ""
        return "\(replayPositionDescription). \(blackCount) black stones and \(whiteCount) white stones.\(result)"
    }

    private var playbackControls: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Move \(moveIndex) of \(game.moves.count)")
                    .font(.headline.monospacedDigit())
                HStack(spacing: 8) {
                    if let selectedMove { StoneDot(player: selectedMove.player) }
                    Text(selectedMoveSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Slider(
                value: Binding(
                    get: { Double(moveIndex) },
                    set: {
                        stopPlayback()
                        moveIndex = min(game.moves.count, max(0, Int($0.rounded())))
                    }
                ),
                in: 0...Double(max(1, game.moves.count)),
                step: 1,
                onEditingChanged: { isEditing in
                    if isEditing { stopPlayback() }
                }
            )
            .disabled(game.moves.isEmpty)
            .accessibilityLabel("Replay position")
            .accessibilityValue(replayPositionDescription)

            HStack(spacing: 12) {
                transportButton("Previous move", systemImage: "backward.frame") { step(-1) }
                    .disabled(moveIndex == 0)
                transportButton(isPlaying ? "Pause replay" : "Play replay", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    isPlaying ? stopPlayback() : startPlayback()
                }
                .disabled(game.moves.isEmpty)
                transportButton("Next move", systemImage: "forward.frame") { step(1) }
                    .disabled(moveIndex == game.moves.count)
                transportButton("Final position", systemImage: "forward.end") {
                    stopPlayback()
                    moveIndex = game.moves.count
                }
                .disabled(moveIndex == game.moves.count)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func transportButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(title)
    }

    private func step(_ delta: Int) {
        stopPlayback()
        moveIndex = min(game.moves.count, max(0, moveIndex + delta))
    }

    private func startPlayback() {
        if moveIndex == game.moves.count { moveIndex = 0 }
        isPlaying = true
        playbackTask = Task {
            while !Task.isCancelled, moveIndex < game.moves.count {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                moveIndex += 1
            }
            isPlaying = false
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }
}

struct StoneDot: View {
    @Environment(\.colorScheme) private var colorScheme
    let player: Player?
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let player {
                Circle().fill(player == .black ? Color.black : Color.white)
                    .overlay(Circle().stroke(.secondary, lineWidth: player == .white || colorScheme == .dark ? 1 : 0))
            } else {
                Image(systemName: "equal")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
