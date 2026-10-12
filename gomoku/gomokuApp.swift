//
//  gomokuApp.swift
//  gomoku
//
//  Created by Li Zheng on 11/11/25.
//

import SwiftData
import SwiftUI

@main
struct GomokuApp: App {
    @StateObject private var game: GameState
    @StateObject private var preferences: PreferencesStore
    private let archiveContainer: ModelContainer

    init() {
        #if DEBUG
        if let fixture = UITestFixtures.makeIfRequested() {
            _game = StateObject(wrappedValue: fixture.game)
            _preferences = StateObject(wrappedValue: fixture.preferences)
            archiveContainer = fixture.archive
            return
        }
        #endif
        _game = StateObject(wrappedValue: GameState())
        _preferences = StateObject(wrappedValue: PreferencesStore())
        archiveContainer = ArchiveContainer.make()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .environmentObject(preferences)
                #if DEBUG
                .modifier(UITestDynamicTypeModifier())
                #endif
        }
        .modelContainer(archiveContainer)
        .commands { GameCommands() }
    }
}

#if DEBUG
private struct UITestDynamicTypeModifier: ViewModifier {
    func body(content: Content) -> some View {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--ui-testing-largest-text") {
            content.dynamicTypeSize(.accessibility5)
        } else {
            content
        }
    }
}
#endif

struct GameActions {
    let newRound: () -> Void
    let undo: () -> Void
    let hint: () -> Void
    let canUndo: Bool
    let canHint: Bool
}

private struct GameActionsKey: FocusedValueKey {
    typealias Value = GameActions
}

extension FocusedValues {
    var gameActions: GameActions? {
        get { self[GameActionsKey.self] }
        set { self[GameActionsKey.self] = newValue }
    }
}

private struct GameCommands: Commands {
    @FocusedValue(\.gameActions) private var actions

    var body: some Commands {
        CommandMenu("Game") {
            Button("New Game", systemImage: "plus.circle") { actions?.newRound() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("Undo", systemImage: "arrow.uturn.backward") { actions?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(actions?.canUndo != true)
            Divider()
            Button("Hint", systemImage: "lightbulb") { actions?.hint() }
                .keyboardShortcut("h", modifiers: .command)
                .disabled(actions?.canHint != true)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(GameState())
        .environmentObject(PreferencesStore())
        .modelContainer(ArchiveContainer.make())
}
