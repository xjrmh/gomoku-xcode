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
        _game = StateObject(wrappedValue: GameState())
        _preferences = StateObject(wrappedValue: PreferencesStore())
        archiveContainer = ArchiveContainer.make()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .environmentObject(preferences)
        }
        .modelContainer(archiveContainer)
        .commands { GameCommands() }
    }
}

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
            Button("New Round", systemImage: "arrow.clockwise") { actions?.newRound() }
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
