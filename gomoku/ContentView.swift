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
    let theme: BoardTheme
}

struct ContentView: View {
    @EnvironmentObject private var game: GameState
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var presentedSheet: GameSheet?
    @State private var sharePayload: SharePayload?
    @State private var didBootstrap = false

    private var palette: GomokuPalette { .resolve(colorScheme, theme: preferences.theme) }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    GameplayLayout(viewportHeight: proxy.size.height) {
                        gameplayControls
                        MatchHUD(game: game, theme: preferences.theme)
                        boardSection
                        VStack(spacing: 10) {
                            auxiliaryControls
                            MatchDock(game: game, sharePayload: sharePayload) {
                                presentedSheet = .newGame
                            }
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
            .toolbar(.hidden, for: .navigationBar)
            #endif
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
            .task(id: ShareRenderIdentity(sessionID: game.session.id, archived: game.session.archived,
                                         colorScheme: colorScheme, theme: preferences.theme)) {
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
            BoardCanvasView(game: game, palette: palette)
                .id(game.session.id)
            Text("Move \(game.moves.count)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("move-count")
        }
    }

    private var auxiliaryControls: some View {
        let showsTip = game.boardSize >= 19 && !preferences.didShowPrecisionCoachMark && !game.gameOver
        return ZStack {
            PrecisionCoachMark { preferences.didShowPrecisionCoachMark = true }
                .opacity(showsTip ? 1 : 0)
                .disabled(!showsTip)
                .allowsHitTesting(showsTip)
                .accessibilityHidden(!showsTip)
            AdaptiveGlassButton(prominent: true) { game.newRound() } label: {
                Label("Play Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .controlSize(.large)
            .opacity(game.gameOver ? 1 : 0)
            .disabled(!game.gameOver)
            .allowsHitTesting(game.gameOver)
            .accessibilityHidden(!game.gameOver)
        }
    }

    private var gameplayControls: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                NavigationLink {
                    HistoryView()
                        #if os(iOS)
                        .toolbar(.visible, for: .navigationBar)
                        #endif
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("History")
                Button { presentedSheet = .settings } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
                #if os(macOS)
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("About Just Gomoku", systemImage: "info.circle") { presentedSheet = .about }
                }
                .frame(width: 44, height: 44)
                #endif
            }
            .font(.system(size: 20))
            .buttonStyle(.plain)
            .adaptiveGlass(cornerRadius: 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("gameplay-controls")
        }
    }

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        game.configureArchive(
            completion: { ArchiveRepository.archive($0, theme: preferences.theme, in: modelContext) },
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
        case .placement: message = preferences.theme.statusText(for: game)
        case .invalidPlacement: message = "That position is unavailable"
        case .undo: message = "Move undone. \(preferences.theme.statusText(for: game))"
        case .hint: message = game.hint.map { "Hint: \($0.coordinate)" }
        case .newRound: message = "New round. \(preferences.theme.playerName(.black))'s turn"
        case .win: message = game.winner.map { "\(preferences.theme.playerName($0)) wins" }
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

// All surfaces share one column. A measured auxiliary slot keeps the board and
// scroll extent stable when tips or result actions appear and disappear.
private struct GameplayLayout: Layout {
    let viewportHeight: CGFloat

    private struct Measurements {
        let dimensions: [CGSize]
        let positions: [CGFloat]
        var minimumHeight: CGFloat { positions[3] + dimensions[3].height + 8 }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> Measurements {
        let columnWidth = max(0, min(720, width - 16))
        let dimensions = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
        }
        let controlsTop: CGFloat = 8
        let hudTop = controlsTop + dimensions[0].height + 8
        let hudBottom = hudTop + dimensions[1].height
        let footerTop = viewportHeight - dimensions[3].height - 8
        let boardTop = max(hudBottom + 16,
                           (hudBottom + footerTop - dimensions[2].height) / 2)
        let dockTop = max(boardTop + dimensions[2].height + 16,
                          viewportHeight - dimensions[3].height - 8)
        return Measurements(dimensions: dimensions, positions: [controlsTop, hudTop, boardTop, dockTop])
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 390
        let sizes = measure(width: width, subviews: subviews)
        return CGSize(width: width, height: max(viewportHeight, sizes.minimumHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.midX, y: bounds.minY + sizes.positions[index]),
                anchor: .top,
                proposal: ProposedViewSize(sizes.dimensions[index])
            )
        }
    }
}

private struct PrecisionCoachMark: View {
    let dismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { content }
            } else {
                HStack(spacing: 12) { content }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        Label("Hold, drag, and release for precise placement.", systemImage: "hand.draw")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        Button("Got it", action: dismiss)
            .font(.callout.weight(.semibold))
            .fixedSize()
            .frame(minHeight: 44)
    }
}

private struct MatchHUD: View {
    @ObservedObject var game: GameState
    let theme: BoardTheme
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("match-hud")
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
            StoneDot(player: game.outcome == .draw ? nil : (game.winner ?? game.current), theme: theme)
            // Reserve every status label so a result or turn change
            // cannot switch the HUD between its compact and expanded layouts.
            ZStack(alignment: .leading) {
                ForEach(["\(theme.playerName(.black))'s turn", "\(theme.playerName(.white))'s turn", "AI thinking…", "Your move",
                         "\(theme.playerName(.black)) wins", "\(theme.playerName(.white)) wins", "Draw"], id: \.self) { status in
                    Text(status).hidden()
                }
                Text(theme.statusText(for: game))
            }
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(game.session.configuration.mode == .ai && !game.gameOver
            ? "\(theme.statusText(for: game)), \(theme.accessibilityName(game.current)) pieces" : theme.statusText(for: game))
    }

    private func clock(for player: Player, now: Date) -> some View {
        let value = time(game.elapsed(for: player, now: now))
        return HStack(spacing: 6) {
            StoneDot(player: player, size: 13, theme: theme)
            Text(value)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.primary.opacity(0.7))
                .fixedSize()
                .accessibilityLabel("\(theme.accessibilityName(player)) elapsed time, \(value)")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("match-dock")
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
                ZStack {
                    MinimalDockLabel("Share", systemImage: "square.and.arrow.up")
                        .hidden()
                    ProgressView()
                        .accessibilityLabel("Preparing result")
                }
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
    @EnvironmentObject private var preferences: PreferencesStore
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
                        Text(sideTitle(.black)).tag(Player.black)
                        Text(sideTitle(.white)).tag(Player.white)
                    }
                    .accessibilityIdentifier("new-game-stones")
                }
            } header: {
                Text("Players")
            } footer: {
                Text("\(sideTitle(.black)) moves first.")
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            startButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private var startButton: some View {
        AdaptiveGlassButton(prominent: true) {
            if game.moves.isEmpty || game.gameOver { startGame() }
            else { showResetConfirmation = true }
        } label: {
            Text("Start Game")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("start-game")
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

    private func sideTitle(_ player: Player) -> String {
        preferences.theme == .standard ? player.name : "\(preferences.theme.playerName(player)) (\(player.name))"
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
                NavigationLink {
                    ThemeSettingsView()
                } label: {
                    HStack {
                        Text("Theme")
                        Spacer()
                        Text(preferences.theme.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings-theme")
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

    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image("GomokuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)
                    Text("Just Gomoku")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("The classic five-in-a-row game.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let version {
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Play against the built-in AI or a friend on the same device. Replay past games, one move at a time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)

                Divider()

                Link(destination: URL(string: "https://flatre.ai")!) {
                    Image("FlatreLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Flatre website")
                .accessibilityHint("Opens flatre.ai in your browser")
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
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
