import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject private var game: GameState
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @SceneStorage("matchInspectorExpanded") private var inspectorExpanded = true
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var sharePayload: SharePayload?
    @State private var didBootstrap = false

    private var palette: GomokuPalette { .resolve(colorScheme) }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    palette.background.ignoresSafeArea()
                    if proxy.size.width >= 800 {
                        wideLayout
                    } else {
                        compactLayout
                    }
                }
            }
            .navigationTitle("Gomoku")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(game: game)
                        .environmentObject(preferences)
                }
            }
            .sheet(isPresented: $showAbout) { AboutView() }
            .preferredColorScheme(preferences.appearance.preferredColorScheme)
            .modifier(HapticFeedbackModifier(pulse: game.feedbackPulse, enabled: preferences.hapticsEnabled))
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { game.sceneBecameActive() } else { game.sceneBecameInactive() }
            }
            .onChange(of: game.feedbackPulse) { _, pulse in announce(pulse.event) }
            .onChange(of: game.session.configuration) { _, configuration in
                preferences.apply(configuration: configuration)
            }
            .task(id: game.session.archived) {
                sharePayload = game.gameOver
                    ? ShareCardRenderer.render(session: game.session, palette: palette, colorScheme: colorScheme)
                    : nil
            }
            .onAppear { bootstrap() }
        }
        .focusedSceneValue(\.gameActions, GameActions(
            newRound: { game.newRound() },
            undo: { game.undo() },
            hint: { game.askForHint() },
            canUndo: game.canUndo,
            canHint: game.canHint
        ))
    }

    private var compactLayout: some View {
        VStack(spacing: 12) {
            GameHeader(game: game)
            StatusChip(game: game)
            ZStack(alignment: .top) {
                BoardCanvasView(game: game, palette: palette)
                precisionCoachMark
            }
            .padding(.horizontal, 8)
            .layoutPriority(1)
            MatchDock(game: game, sharePayload: sharePayload)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    private var wideLayout: some View {
        GeometryReader { proxy in
            let inspectorWidth: CGFloat = inspectorExpanded ? 290 : 44
            let availableWidth = proxy.size.width - inspectorWidth - 64
            let availableHeight = proxy.size.height - 70
            let boardSide = max(320, min(availableWidth, availableHeight))

            VStack(spacing: 16) {
                GameHeader(game: game)
                    .frame(maxWidth: 720)
                HStack(alignment: .top, spacing: 20) {
                    ZStack(alignment: .top) {
                        BoardCanvasView(game: game, palette: palette)
                        precisionCoachMark
                    }
                    .frame(width: boardSide, height: boardSide)

                    if inspectorExpanded {
                        MatchInspector(game: game, sharePayload: sharePayload) {
                            withAnimation(.snappy) { inspectorExpanded = false }
                        }
                        .frame(width: 290, height: boardSide)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        Button("Show match inspector", systemImage: "sidebar.right") {
                            withAnimation(.snappy) { inspectorExpanded = true }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Shows clocks and game actions")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var precisionCoachMark: some View {
        if game.boardSize >= 19, !preferences.didShowPrecisionCoachMark {
            HStack(spacing: 10) {
                Image(systemName: "hand.draw")
                Text("Hold, drag, and release for precise placement.")
                    .font(.callout)
                Button("Got it") { preferences.didShowPrecisionCoachMark = true }
                    .font(.callout.bold())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .adaptiveGlass(cornerRadius: 18, interactive: true)
            .padding(12)
            .transition(.move(edge: .top).combined(with: .opacity))
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
            Button("Settings", systemImage: "gearshape") { showSettings = true }
            Menu("More", systemImage: "ellipsis.circle") {
                Button("About Just Gomoku", systemImage: "info.circle") { showAbout = true }
            }
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

private struct GameHeader: View {
    @ObservedObject var game: GameState

    var body: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: Binding(
                get: { game.session.configuration.mode },
                set: { game.setMode($0) }
            )) {
                ForEach(GameMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            if game.session.configuration.mode == .ai {
                Picker("Difficulty", selection: Binding(
                    get: { game.session.configuration.difficulty },
                    set: { game.setDifficulty($0) }
                )) {
                    ForEach(AIDifficulty.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .padding(.horizontal)
    }
}

private struct StatusChip: View {
    @ObservedObject var game: GameState

    var body: some View {
        Label {
            Text(game.statusText).font(.callout.weight(.semibold))
        } icon: {
            StoneDot(player: game.outcome == .draw ? nil : (game.winner ?? game.current))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .adaptiveGlass(cornerRadius: 18)
        .animation(.snappy, value: game.statusText)
        .accessibilityElement(children: .combine)
    }
}

private struct MatchDock: View {
    @ObservedObject var game: GameState
    let sharePayload: SharePayload?

    var body: some View {
        VStack(spacing: 12) {
            if game.gameOver {
                HStack(spacing: 10) {
                    StoneDot(player: game.winner)
                    Text(game.statusText)
                        .font(.title2.bold())
                    Spacer()
                }
            }
            ClockSummary(game: game)
            actions
        }
        .padding(14)
        .adaptiveGlass(cornerRadius: 26)
        .animation(.snappy, value: game.gameOver)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if game.gameOver {
                AdaptiveGlassButton(prominent: true) { game.newRound() } label: {
                    Label("New Round", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
            }
            AdaptiveGlassButton { game.undo() } label: {
                if game.gameOver {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 30)
                } else {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(minWidth: 44, minHeight: 30)
                }
            }
            .disabled(!game.canUndo)

            if game.gameOver {
                AdaptiveShareButton(payload: sharePayload)
            } else {
                AdaptiveGlassButton { game.askForHint() } label: {
                    Label("Hint", systemImage: "lightbulb")
                        .frame(minWidth: 44, minHeight: 30)
                }
                .disabled(!game.canHint)
            }
        }
    }
}

private struct MatchInspector: View {
    @ObservedObject var game: GameState
    let sharePayload: SharePayload?
    let collapse: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text(game.gameOver ? game.statusText : "Match")
                    .font(.title2.bold())
                Spacer()
                Button("Collapse inspector", systemImage: "chevron.right", action: collapse)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
            StatusChip(game: game)
            ClockSummary(game: game)
            Spacer()
            VStack(spacing: 12) {
                if game.gameOver {
                    AdaptiveGlassButton(prominent: true) { game.newRound() } label: {
                        Label("New Round", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                }
                AdaptiveGlassButton { game.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 34)
                }
                .disabled(!game.canUndo)
                if game.gameOver {
                    AdaptiveShareButton(payload: sharePayload, expand: true)
                } else {
                    AdaptiveGlassButton { game.askForHint() } label: {
                        Label("Hint", systemImage: "lightbulb").frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .disabled(!game.canHint)
                }
            }
        }
        .padding(20)
        .adaptiveGlass(cornerRadius: 28)
    }
}

private struct ClockSummary: View {
    @ObservedObject var game: GameState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 10) {
                Label("Moves \(game.moves.count)", systemImage: "number")
                Divider().frame(height: 18)
                Label(time(game.elapsed(for: .black, now: timeline.date)), systemImage: "circle.fill")
                    .symbolRenderingMode(.monochrome)
                Divider().frame(height: 18)
                Label(time(game.elapsed(for: .white, now: timeline.date)), systemImage: "circle")
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .accessibilityElement(children: .combine)
        }
    }

    private func time(_ value: TimeInterval) -> String {
        let seconds = Int(value.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct AdaptiveShareButton: View {
    let payload: SharePayload?
    var expand = false

    var body: some View {
        if let payload {
            if #available(iOS 26.0, macOS 26.0, *) {
                ShareLink(item: payload, preview: SharePreview("Just Gomoku result")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: expand ? .infinity : nil, minHeight: 34)
                }
                .buttonStyle(.glass)
            } else {
                ShareLink(item: payload, preview: SharePreview("Just Gomoku result")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: expand ? .infinity : nil, minHeight: 34)
                }
                .buttonStyle(.bordered)
            }
        } else {
            ProgressView().frame(minWidth: 44, minHeight: 44)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var game: GameState
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingSize: Int?
    @State private var pendingSide: Player?
    @State private var customSize = 15
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Board") {
                Picker("Board Size", selection: Binding(
                    get: { game.boardSize },
                    set: { requestBoardSize($0) }
                )) {
                    Text("9×9").tag(9)
                    Text("15×15").tag(15)
                    Text("19×19").tag(19)
                    Text("Custom (\(customSize)×\(customSize))").tag(customSize)
                }
                Stepper("Custom: \(customSize)×\(customSize)", value: $customSize, in: 5...25, step: 2)
                Button("Use Custom Size") { requestBoardSize(customSize) }
            }

            Section("Opponent") {
                Picker("Difficulty", selection: Binding(
                    get: { game.session.configuration.difficulty },
                    set: { game.setDifficulty($0) }
                )) {
                    ForEach(AIDifficulty.allCases) { Text($0.title).tag($0) }
                }
                .disabled(game.session.configuration.mode != .ai)

                Picker("Your Stones", selection: Binding(
                    get: { game.session.configuration.humanSide },
                    set: { requestSide($0) }
                )) {
                    Text("Black").tag(Player.black)
                    Text("White").tag(Player.white)
                }
                .disabled(game.session.configuration.mode != .ai)
            }

            Section("Appearance & Feel") {
                Picker("Appearance", selection: Binding(
                    get: { preferences.appearance },
                    set: { preferences.appearance = $0 }
                )) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Haptics", isOn: Binding(
                    get: { preferences.hapticsEnabled },
                    set: { preferences.hapticsEnabled = $0 }
                ))
            }

            Section {
                Button("Restart Current Game", systemImage: "arrow.counterclockwise") {
                    if game.moves.isEmpty {
                        game.newRound()
                    } else {
                        showResetConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onAppear { customSize = game.boardSize }
        .confirmationDialog("Start a new game?", isPresented: Binding(
            get: { pendingSize != nil || pendingSide != nil || showResetConfirmation },
            set: { if !$0 { pendingSize = nil; pendingSide = nil; showResetConfirmation = false } }
        ), titleVisibility: .visible) {
            Button("Start New Game", role: .destructive) { applyPendingReset() }
            Button("Cancel", role: .cancel) { clearPending() }
        } message: {
            Text("The current board will be cleared.")
        }
    }

    private func requestBoardSize(_ size: Int) {
        guard size != game.boardSize else { return }
        if game.moves.isEmpty { game.setBoardSizeAndStartNewRound(size) } else { pendingSize = size }
    }

    private func requestSide(_ side: Player) {
        guard side != game.session.configuration.humanSide else { return }
        if game.moves.isEmpty { game.setHumanSideAndStartNewRound(side) } else { pendingSide = side }
    }

    private func applyPendingReset() {
        if let pendingSize { game.setBoardSizeAndStartNewRound(pendingSize) }
        else if let pendingSide { game.setHumanSideAndStartNewRound(pendingSide) }
        else { game.newRound() }
        clearPending()
    }

    private func clearPending() {
        pendingSize = nil
        pendingSide = nil
        showResetConfirmation = false
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Just Gomoku").font(.title.bold())
            Text("A private, focused Gomoku game for your Apple devices.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text("Created by")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://flatre.ai")!) {
                    HStack(spacing: 8) {
                        Image("FlatreLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .accessibilityHidden(true)
                        Text("Flatre.ai")
                            .font(.headline)
                    }
                }

                Link(destination: URL(string: "mailto:li@flatre.ai")!) {
                    Label("li@flatre.ai", systemImage: "envelope")
                }
                .font(.footnote)
            }

            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding(32)
        .presentationDetents([.medium])
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
