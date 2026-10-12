import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum GameSheet: String, Identifiable {
    case newGame, settings, about
    var id: Self { self }
}

private struct ShareRenderIdentity: Equatable {
    let sessionID: UUID
    let archived: Bool
    let colorScheme: ColorScheme
}

struct ContentView: View {
    @EnvironmentObject private var game: GameState
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedSheet: GameSheet?
    @State private var sharePayload: SharePayload?
    @State private var didBootstrap = false

    private var palette: GomokuPalette { .resolve(colorScheme) }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    GameplayLayout(viewportHeight: proxy.size.height, accessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                        MatchHUD(game: game)
                        boardSection
                        MatchDock(game: game, sharePayload: sharePayload) {
                            presentedSheet = .newGame
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .background(palette.background.ignoresSafeArea())
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .sheet(item: $presentedSheet) { destination in
                NavigationStack {
                    switch destination {
                    case .newGame: NewGameView(game: game)
                    case .settings: SettingsView().environmentObject(preferences)
                    case .about: AboutView().presentationDetents([.medium, .large])
                    }
                }
                .preferredColorScheme(preferences.appearance.preferredColorScheme)
            }
            .preferredColorScheme(preferences.appearance.preferredColorScheme)
            .modifier(HapticFeedbackModifier(pulse: game.feedbackPulse, enabled: preferences.hapticsEnabled))
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { game.sceneBecameActive() } else { game.sceneBecameInactive() }
            }
            .onChange(of: game.feedbackPulse) { _, pulse in announce(pulse.event) }
            .onChange(of: game.session.configuration) { _, configuration in
                preferences.apply(configuration: configuration)
            }
            .task(id: ShareRenderIdentity(sessionID: game.session.id, archived: game.session.archived, colorScheme: colorScheme)) {
                sharePayload = game.gameOver
                    ? ShareCardRenderer.render(session: game.session, palette: palette, colorScheme: colorScheme)
                    : nil
                #if DEBUG
                if let sharePayload { UITestFixtures.recordShareCard(sharePayload, colorScheme: colorScheme) }
                #endif
                #if DEBUG && os(iOS)
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                    try? await Task.sleep(for: .milliseconds(300))
                    UITestFixtures.recordScrollMetrics()
                }
                #endif
            }
            .onAppear { bootstrap() }
        }
        .focusedSceneValue(\.gameActions, GameActions(
            newRound: { presentedSheet = .newGame },
            undo: { game.undo() },
            hint: { game.askForHint() },
            canUndo: game.canUndo,
            canHint: game.canHint
        ))
    }

    private var boardSection: some View {
        VStack(alignment: .trailing, spacing: 10) {
            precisionCoachMark
            BoardCanvasView(game: game, palette: palette)
                .id(game.session.id)
            Text("Move \(game.moves.count)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("move-count")
        }
    }

    @ViewBuilder
    private var precisionCoachMark: some View {
        if game.boardSize >= 19, !preferences.didShowPrecisionCoachMark {
            VStack(alignment: .leading, spacing: 4) {
                Label("Hold, drag, and release for precise placement.", systemImage: "hand.draw")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Got it") { preferences.didShowPrecisionCoachMark = true }
                    .font(.callout.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            NavigationLink {
                HistoryView()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            Button("Settings", systemImage: "gearshape") { presentedSheet = .settings }
            #if os(macOS)
            Menu("More", systemImage: "ellipsis.circle") {
                Button("About Just Gomoku", systemImage: "info.circle") { presentedSheet = .about }
            }
            #endif
        }
    }

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        game.configureArchive(
            completion: { ArchiveRepository.archive($0, in: modelContext) },
            reopen: { ArchiveRepository.reopen($0, in: modelContext) }
        )
        if game.moves.isEmpty, !game.gameOver {
            let saved = preferences.payload
            let configuration = GameConfiguration(
                mode: saved.defaultMode,
                boardSize: saved.boardSize,
                difficulty: saved.difficulty,
                humanSide: saved.humanSide
            )
            if game.session.configuration != configuration { game.newRound(configuration: configuration) }
        }
        if scenePhase == .active { game.sceneBecameActive() }
    }

    private func announce(_ event: HapticEvent) {
        let message: String?
        switch event {
        case .placement: message = game.statusText
        case .invalidPlacement: message = "That position is unavailable"
        case .undo: message = "Move undone. \(game.statusText)"
        case .hint: message = game.hint.map { "Hint: \($0.coordinate)" }
        case .newRound: message = "New round. Black's turn"
        case .win: message = game.winner.map { "\($0.name) wins" }
        case .draw: message = "Draw"
        case .none, .targetChanged: message = nil
        }
        guard let message else { return }
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: message)
        #elseif os(macOS)
        guard let application = NSApp else { return }
        NSAccessibility.post(element: application, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        #endif
    }
}

// Measure the status and actions before allocating board space. Short windows and
// larger text grow the scrollable content instead of placing views over the board.
private struct GameplayLayout: Layout {
    let viewportHeight: CGFloat
    let accessibilitySize: Bool

    private struct Measurements {
        let hud: CGSize
        let board: CGSize
        let dock: CGSize
        var minimumHeight: CGFloat { hud.height + board.height + dock.height + 44 }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> Measurements {
        let hudWidth = max(0, min(720, width - 16))
        let dockWidth = max(0, min(480, width - 24))
        let hud = subviews[0].sizeThatFits(ProposedViewSize(width: hudWidth, height: nil))
        let dock = subviews[2].sizeThatFits(ProposedViewSize(width: dockWidth, height: nil))
        let maximumBoardWidth = max(0, min(720, width - 28))
        var board = subviews[1].sizeThatFits(ProposedViewSize(width: maximumBoardWidth, height: nil))
        if !accessibilitySize {
            let overflow = max(0, hud.height + board.height + dock.height + 44 - viewportHeight)
            let boardWidth = max(min(240, maximumBoardWidth), maximumBoardWidth - overflow)
            board = subviews[1].sizeThatFits(ProposedViewSize(width: boardWidth, height: nil))
        }
        return Measurements(hud: hud, board: board, dock: dock)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 390
        let sizes = measure(width: width, subviews: subviews)
        return CGSize(width: width, height: max(viewportHeight, sizes.minimumHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(width: bounds.width, subviews: subviews)
        let hudTop = bounds.minY + 8
        let dockTop = bounds.maxY - sizes.dock.height - 8
        let boardTop = hudTop + sizes.hud.height + (dockTop - hudTop - sizes.hud.height - sizes.board.height) / 2
        let positions = [hudTop, boardTop, dockTop]
        let dimensions = [sizes.hud, sizes.board, sizes.dock]
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.midX, y: positions[index]),
                anchor: .top,
                proposal: ProposedViewSize(dimensions[index])
            )
        }
    }
}

private struct MatchHUD: View {
    @ObservedObject var game: GameState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var modeDescription: String {
        game.session.configuration.mode == .ai ? "AI · \(game.session.configuration.difficulty.title)" : "2 Players"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    expandedLayout(now: timeline.date)
                } else {
                    ViewThatFits(in: .horizontal) {
                        compactLayout(now: timeline.date)
                        expandedLayout(now: timeline.date)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private func compactLayout(now: Date) -> some View {
        HStack(spacing: 12) {
            turnSummary
            Spacer(minLength: 0)
            clock(for: .black, now: now)
            clock(for: .white, now: now)
            Divider().frame(height: 20)
            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.7))
                .fixedSize()
        }
    }

    private func expandedLayout(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            turnSummary
            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    clock(for: .black, now: now)
                    clock(for: .white, now: now)
                }
                VStack(alignment: .leading, spacing: 10) {
                    clock(for: .black, now: now)
                    clock(for: .white, now: now)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var turnSummary: some View {
        HStack(spacing: 8) {
            StoneDot(player: game.outcome == .draw ? nil : (game.winner ?? game.current))
            Text(game.statusText)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(game.session.configuration.mode == .ai && !game.gameOver
            ? "\(game.statusText), \(game.current.name) stones" : game.statusText)
    }

    private func clock(for player: Player, now: Date) -> some View {
        let value = time(game.elapsed(for: player, now: now))
        return HStack(spacing: 6) {
            StoneDot(player: player, size: 13)
            Text(value)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.primary.opacity(0.7))
                .fixedSize()
                .accessibilityLabel("\(player.name) elapsed time, \(value)")
                .accessibilityIdentifier(player == .black ? "black-clock" : "white-clock")
        }
        .frame(minHeight: 44)
    }

    private func time(_ value: TimeInterval) -> String {
        let seconds = Int(value.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct MatchDock: View {
    @ObservedObject var game: GameState
    let sharePayload: SharePayload?
    let newGame: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AdaptiveGlassContainer {
            VStack(spacing: 10) {
                if game.gameOver {
                    AdaptiveGlassButton(prominent: true) { game.newRound() } label: {
                        Label("Play Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .controlSize(.large)
                }
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 4) { actions }
                    } else {
                        HStack(spacing: 4) { actions }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .adaptiveGlass(cornerRadius: 30)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        MinimalDockAction("Undo", systemImage: "arrow.uturn.backward") { game.undo() }
            .disabled(!game.canUndo)
        if game.gameOver {
            if let sharePayload {
                ShareLink(item: sharePayload, preview: SharePreview(sharePayload.title, image: sharePayload.previewImage)) {
                    MinimalDockLabel("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(MinimalDockActionStyle())
                .foregroundStyle(.primary)
            } else {
                ProgressView("Preparing result")
                    .frame(maxWidth: .infinity, minHeight: 58)
            }
        } else {
            MinimalDockAction("Hint", systemImage: "lightbulb") { game.askForHint() }
                .disabled(!game.canHint)
        }
        MinimalDockAction("New Game", systemImage: "plus.circle", action: newGame)
    }
}

private struct MinimalDockAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) { MinimalDockLabel(title, systemImage: systemImage) }
            .buttonStyle(MinimalDockActionStyle())
            .foregroundStyle(.primary)
    }
}

private struct MinimalDockLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    icon
                    Text(title)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 5) {
                    icon
                    Text(title)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .contentShape(Rectangle())
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .regular))
            .frame(width: 28, height: 24)
    }
}

private struct MinimalDockActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.32)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct NewGameView: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GameConfiguration
    @State private var boardChoice: Int
    @State private var showResetConfirmation = false

    init(game: GameState) {
        self.game = game
        _draft = State(initialValue: game.session.configuration)
        let size = game.boardSize
        _boardChoice = State(initialValue: [9, 15, 19].contains(size) ? size : 0)
    }

    var body: some View {
        Form {
            Section {
                Picker("Opponent", selection: $draft.mode) {
                    Text("2 Players").tag(GameMode.pvp)
                    Text("AI").tag(GameMode.ai)
                }
                .accessibilityIdentifier("new-game-opponent")
                if draft.mode == .ai {
                    Picker("Difficulty", selection: $draft.difficulty) {
                        ForEach(AIDifficulty.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("new-game-difficulty")
                    Picker("Your Stones", selection: $draft.humanSide) {
                        Text("Black").tag(Player.black)
                        Text("White").tag(Player.white)
                    }
                    .accessibilityIdentifier("new-game-stones")
                }
            } header: {
                Text("Players")
            } footer: {
                Text("Black moves first.")
            }
            Section {
                Picker("Board Size", selection: $boardChoice) {
                    Text("9×9").tag(9)
                    Text("15×15").tag(15)
                    Text("19×19").tag(19)
                    Text("Custom").tag(0)
                }
                .accessibilityIdentifier("new-game-board-size")
                if boardChoice == 0 {
                    Stepper("Custom Size: \(draft.boardSize)×\(draft.boardSize)", value: $draft.boardSize, in: 5...25, step: 2)
                        .accessibilityIdentifier("custom-board-size")
                }
            } header: {
                Text("Board")
            } footer: {
                Text("Connect five stones in a row to win.")
            }
        }
        .pickerStyle(.menu)
        .navigationTitle("New Game")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") {
                    if game.moves.isEmpty || game.gameOver { startGame() }
                    else { showResetConfirmation = true }
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("start-game")
            }
        }
        .confirmationDialog("Start a new game?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Start New Game", role: .destructive) { startGame() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The current board will be cleared.")
        }
    }

    private func startGame() {
        var configuration = draft
        if boardChoice != 0 { configuration.boardSize = boardChoice }
        configuration.normalize()
        game.newRound(configuration: configuration)
        dismiss()
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Appearance & Feel") {
                Picker("Appearance", selection: Binding(
                    get: { preferences.appearance },
                    set: { preferences.appearance = $0 }
                )) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings-appearance")
                Toggle("Haptics", isOn: Binding(
                    get: { preferences.hapticsEnabled },
                    set: { preferences.hapticsEnabled = $0 }
                ))
            }
            Section("About") {
                NavigationLink {
                    AboutView(showsDone: false)
                } label: {
                    Label("About Just Gomoku", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var showsDone = true

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("GomokuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 68, height: 68)
                        .accessibilityHidden(true)
                    Text("Just Gomoku").font(.title2.bold())
                    Text("Private, focused Gomoku for your Apple devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section("Creator") {
                Link(destination: URL(string: "https://flatre.ai")!) {
                    Label("Flatre.ai", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "mailto:li@flatre.ai")!) {
                    Label("li@flatre.ai", systemImage: "envelope")
                }
            }
        }
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct HapticFeedbackModifier: ViewModifier {
    let pulse: HapticPulse
    let enabled: Bool

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: pulse) { _, new in
            guard enabled else { return nil }
            switch new.event {
            case .placement:
                return .impact(flexibility: .rigid, intensity: 0.72)
            case .targetChanged, .hint:
                return .selection
            case .invalidPlacement:
                return .warning
            case .undo:
                return .impact(flexibility: .soft, intensity: 0.45)
            case .newRound, .draw:
                return .impact(weight: .medium, intensity: 0.55)
            case .win:
                return .success
            case .none:
                return nil
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(GameState())
        .environmentObject(PreferencesStore())
        .modelContainer(ArchiveContainer.make())
}
