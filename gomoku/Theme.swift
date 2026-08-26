import Combine
import Foundation
import SwiftUI

enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct PreferencePayload: Codable, Equatable, Sendable {
    var modifiedAt = Date()
    var appearance: AppAppearance = .system
    var hapticsEnabled = true
    var defaultMode: GameMode = .pvp
    var boardSize = 15
    var difficulty: AIDifficulty = .medium
    var humanSide: Player = .white
    var didShowPrecisionCoachMark = false
}

@MainActor
final class PreferencesStore: NSObject, ObservableObject {
    static let localKey = "just-gomoku.preferences.v1"
    static let cloudKey = "just-gomoku.preferences.cloud.v1"

    @Published var payload: PreferencePayload {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore
    private var applyingRemoteValue = false

    init(
        defaults: UserDefaults = .standard,
        cloud: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.cloud = cloud
        let local = defaults.data(forKey: Self.localKey).flatMap {
            try? JSONDecoder().decode(PreferencePayload.self, from: $0)
        }
        let remote = cloud.data(forKey: Self.cloudKey).flatMap {
            try? JSONDecoder().decode(PreferencePayload.self, from: $0)
        }
        self.payload = [local, remote].compactMap { $0 }.max(by: { $0.modifiedAt < $1.modifiedAt }) ?? .init()
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudValueChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )
        cloud.synchronize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var appearance: AppAppearance {
        get { payload.appearance }
        set { update { $0.appearance = newValue } }
    }

    var hapticsEnabled: Bool {
        get { payload.hapticsEnabled }
        set { update { $0.hapticsEnabled = newValue } }
    }

    var didShowPrecisionCoachMark: Bool {
        get { payload.didShowPrecisionCoachMark }
        set { update { $0.didShowPrecisionCoachMark = newValue } }
    }

    func apply(configuration: GameConfiguration) {
        update {
            $0.defaultMode = configuration.mode
            $0.boardSize = configuration.boardSize
            $0.difficulty = configuration.difficulty
            $0.humanSide = configuration.humanSide
        }
    }

    private func update(_ mutation: (inout PreferencePayload) -> Void) {
        var copy = payload
        mutation(&copy)
        copy.modifiedAt = .now
        payload = copy
    }

    private func persist() {
        guard !applyingRemoteValue, let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.localKey)
        cloud.set(data, forKey: Self.cloudKey)
        cloud.synchronize()
    }

    private func mergeRemoteValue() {
        guard let data = cloud.data(forKey: Self.cloudKey),
              let remote = try? JSONDecoder().decode(PreferencePayload.self, from: data),
              remote.modifiedAt > payload.modifiedAt else { return }
        applyingRemoteValue = true
        payload = remote
        applyingRemoteValue = false
        defaults.set(data, forKey: Self.localKey)
    }

    @objc private func cloudValueChanged() {
        mergeRemoteValue()
    }
}

struct GomokuPalette {
    let boardWood: Color
    let cellLight: Color
    let cellDark: Color
    let stoneBorder: Color
    let background: Color
    let winningGold: Color

    static func resolve(_ scheme: ColorScheme) -> Self {
        if scheme == .dark {
            return .init(
                boardWood: Color(hex: 0x5B4438),
                cellLight: Color(hex: 0x6A5347),
                cellDark: Color(hex: 0x5D483E),
                stoneBorder: Color.white.opacity(0.6),
                background: Color(hex: 0x111111),
                winningGold: Color(hex: 0xF4C542)
            )
        }
        return .init(
            boardWood: Color(hex: 0x8B4513),
            cellLight: Color(hex: 0xDEB887),
            cellDark: Color(hex: 0xD2A679),
            stoneBorder: Color.black.opacity(0.35),
            background: Color(hex: 0xF8F8F8),
            winningGold: Color(hex: 0xD6A615)
        )
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
