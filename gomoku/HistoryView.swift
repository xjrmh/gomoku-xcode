import SwiftData
import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pvp = "PvP"
    case ai = "AI"

    var id: Self { self }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ArchivedGame.completedAt, order: .reverse) private var games: [ArchivedGame]
    @State private var filter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var showEraseConfirmation = false

    private var palette: GomokuPalette { .resolve(colorScheme) }
    private var filteredGames: [ArchivedGame] {
        games.filter { game in
            let matchesMode = switch filter {
            case .all: true
            case .pvp: game.modes.contains(.pvp)
            case .ai: game.modes.contains(.ai)
            }
            guard matchesMode else { return false }
            guard !searchText.isEmpty else { return true }
            let searchable = [
                game.resultTitle,
                game.finalMode.title,
                game.difficulty.title,
                "\(game.boardSize)x\(game.boardSize)",
                game.completedAt.formatted(date: .abbreviated, time: .omitted)
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            Picker("Game type", selection: $filter) {
                ForEach(HistoryFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if filteredGames.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Games Yet" : "No Matches",
                    systemImage: "square.grid.2x2",
                    description: Text(searchText.isEmpty ? "Completed games will appear here." : "Try another search or filter.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)], spacing: 18) {
                    ForEach(filteredGames) { game in
                        NavigationLink {
                            ReplayView(game: game)
                        } label: {
                            HistoryCard(game: game, palette: palette)
                        }
                        .buttonStyle(.plain)
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

            HStack(spacing: 8) {
                StoneDot(player: game.winner)
                Text(game.resultTitle)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            Text(game.completedAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(metadata)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(game.moveCount) moves")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens move-by-move replay")
    }

    private var metadata: String {
        var parts = [game.finalMode.title]
        if game.finalMode == .ai { parts.append(game.difficulty.title) }
        parts.append("\(game.boardSize)×\(game.boardSize)")
        return parts.joined(separator: " · ")
    }
}

struct ReplayView: View {
    @Environment(\.colorScheme) private var colorScheme
    let game: ArchivedGame
    @State private var moveIndex: Int
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?

    init(game: ArchivedGame) {
        self.game = game
        _moveIndex = State(initialValue: game.moves.count)
    }

    var body: some View {
        VStack(spacing: 16) {
            StaticBoardView(
                board: game.board(after: moveIndex),
                boardSize: game.boardSize,
                lastMove: moveIndex > 0 ? game.moves[moveIndex - 1].pos : nil,
                winningLine: moveIndex == game.moves.count ? game.winningLine : [],
                palette: .resolve(colorScheme)
            )
            .frame(maxWidth: 760, maxHeight: 760)

            VStack(spacing: 12) {
                Text("Move \(moveIndex) of \(game.moves.count)")
                    .font(.headline.monospacedDigit())
                Slider(
                    value: Binding(
                        get: { Double(moveIndex) },
                        set: { moveIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(1, game.moves.count)),
                    step: 1
                )
                .accessibilityLabel("Replay position")

                HStack {
                    Button("Previous", systemImage: "backward.frame") { step(-1) }
                        .disabled(moveIndex == 0)
                    Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                        isPlaying ? stopPlayback() : startPlayback()
                    }
                    Button("Next", systemImage: "forward.frame") { step(1) }
                        .disabled(moveIndex == game.moves.count)
                    Button("Final", systemImage: "forward.end") {
                        stopPlayback()
                        moveIndex = game.moves.count
                    }
                }
                .labelStyle(.iconOnly)
                .controlSize(.large)
            }
            .padding()
            .adaptiveGlass(cornerRadius: 22)
            .frame(maxWidth: 620)
        }
        .padding()
        .navigationTitle(game.resultTitle)
        .onDisappear { playbackTask?.cancel() }
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
    let player: Player?

    var body: some View {
        Group {
            if let player {
                Circle().fill(player == .black ? Color.black : Color.white)
                    .overlay(Circle().stroke(.secondary, lineWidth: player == .white ? 1 : 0))
            } else {
                Image(systemName: "equal")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
