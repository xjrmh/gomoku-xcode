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

enum BoardTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, halloween, christmas, easter, valentines, lunarNewYear
    case space, nature, pets, ocean

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .halloween: "Halloween"
        case .christmas: "Christmas"
        case .easter: "Easter"
        case .valentines: "Valentine’s"
        case .lunarNewYear: "Lunar New Year"
        case .space: "Space"
        case .nature: "Nature"
        case .pets: "Pets"
        case .ocean: "Ocean"
        }
    }

    static let holidays: [Self] = [.halloween, .christmas, .easter, .valentines, .lunarNewYear]
    static let everyday: [Self] = [.space, .nature, .pets, .ocean]

    func playerName(_ player: Player) -> String {
        let names: (String, String) = switch self {
        case .standard: ("Black", "White")
        case .halloween: ("Pumpkin", "Ghost")
        case .christmas: ("Tree", "Snowman")
        case .easter: ("Egg", "Bunny")
        case .valentines: ("Heart", "Love Letter")
        case .lunarNewYear: ("Lantern", "Coin")
        case .space: ("Moon", "Star")
        case .nature: ("Leaf", "Flower")
        case .pets: ("Cat", "Dog")
        case .ocean: ("Shell", "Starfish")
        }
        return player == .black ? names.0 : names.1
    }

    func accessibilityName(_ player: Player) -> String {
        self == .standard ? player.name : "\(playerName(player)), \(player.name) side"
    }

    var pieceDescription: String {
        "\(playerName(.black)) & \(playerName(.white))"
    }

    @MainActor
    func statusText(for game: GameState) -> String {
        switch game.outcome {
        case let .win(player, _): "\(playerName(player)) wins"
        case .draw: "Draw"
        case .ongoing where game.isAIThinking: "AI thinking…"
        case .ongoing where game.session.configuration.mode == .ai: "Your move"
        case .ongoing: "\(playerName(game.current))'s turn"
        }
    }
}

struct PreferencePayload: Codable, Equatable, Sendable {
    var modifiedAt = Date()
    var appearance: AppAppearance = .system
    var theme: BoardTheme = .standard
    var hapticsEnabled = true
    var defaultMode: GameMode = .pvp
    var boardSize = 15
    var difficulty: AIDifficulty = .medium
    var humanSide: Player = .white
    var didShowPrecisionCoachMark = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case modifiedAt, appearance, theme, hapticsEnabled, defaultMode, boardSize
        case difficulty, humanSide, didShowPrecisionCoachMark
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        // Older installs and newer theme names preserve all other saved preferences.
        theme = (try? values.decode(BoardTheme.self, forKey: .theme)) ?? .standard
        hapticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        defaultMode = try values.decodeIfPresent(GameMode.self, forKey: .defaultMode) ?? .pvp
        boardSize = try values.decodeIfPresent(Int.self, forKey: .boardSize) ?? 15
        difficulty = try values.decodeIfPresent(AIDifficulty.self, forKey: .difficulty) ?? .medium
        humanSide = try values.decodeIfPresent(Player.self, forKey: .humanSide) ?? .white
        didShowPrecisionCoachMark = try values.decodeIfPresent(Bool.self, forKey: .didShowPrecisionCoachMark) ?? false
    }
}

@MainActor
final class PreferencesStore: NSObject, ObservableObject {
    static let localKey = "just-gomoku.preferences.v1"
    static let cloudKey = "just-gomoku.preferences.cloud.v1"

    @Published var payload: PreferencePayload {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var applyingRemoteValue = false

    init(
        defaults: UserDefaults = .standard,
        cloud: NSUbiquitousKeyValueStore? = .default
    ) {
        self.defaults = defaults
        self.cloud = cloud
        let local = defaults.data(forKey: Self.localKey).flatMap {
            try? JSONDecoder().decode(PreferencePayload.self, from: $0)
        }
        let remote = cloud?.data(forKey: Self.cloudKey).flatMap {
            try? JSONDecoder().decode(PreferencePayload.self, from: $0)
        }
        self.payload = [local, remote].compactMap { $0 }.max(by: { $0.modifiedAt < $1.modifiedAt }) ?? .init()
        super.init()

        if let cloud {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(cloudValueChanged),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud
            )
            cloud.synchronize()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var appearance: AppAppearance {
        get { payload.appearance }
        set { update { $0.appearance = newValue } }
    }

    var theme: BoardTheme {
        get { payload.theme }
        set {
            guard payload.theme != newValue else { return }
            update { $0.theme = newValue }
        }
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
        cloud?.set(data, forKey: Self.cloudKey)
        cloud?.synchronize()
    }

    private func mergeRemoteValue() {
        guard let data = cloud?.data(forKey: Self.cloudKey),
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
    var theme: BoardTheme = .standard
    let boardSurface: Color
    let boardGrid: Color
    let boardEdge: Color
    let stoneBorder: Color
    let background: Color
    let winningGold: Color

    static func resolve(_ scheme: ColorScheme, theme: BoardTheme = .standard) -> Self {
        if theme != .standard { return themed(scheme, theme: theme) }
        if scheme == .dark {
            return .init(
                boardSurface: Color(hex: 0xB99062),
                boardGrid: Color(hex: 0x68492F),
                boardEdge: Color(hex: 0x9D744C),
                stoneBorder: Color.black.opacity(0.42),
                background: Color(hex: 0x12110F),
                winningGold: Color(hex: 0xF4C542)
            )
        }
        return .init(
            boardSurface: Color(hex: 0xF7DFB8),
            boardGrid: Color(hex: 0xB98252),
            boardEdge: Color(hex: 0xE7B977),
            stoneBorder: Color.black.opacity(0.32),
            background: Color(hex: 0xF7F5F1),
            winningGold: Color(hex: 0xC78F2F)
        )
    }

    private static func themed(_ scheme: ColorScheme, theme: BoardTheme) -> Self {
        let dark = scheme == .dark
        let colors: (surface: UInt32, grid: UInt32, edge: UInt32, background: UInt32) = switch theme {
        case .standard: (0xF7DFB8, 0xB98252, 0xE7B977, 0xF7F5F1)
        case .halloween: dark
            ? (0x534659, 0x8E7F97, 0x74647D, 0x17121C)
            : (0xE9DFF0, 0xA190AC, 0xC4AFD0, 0xF7F3FA)
        case .christmas: dark
            ? (0x8DA99D, 0x456F5C, 0x698F7A, 0x101B17)
            : (0xDFEDE3, 0x85A994, 0xACC9B5, 0xF3F8F4)
        case .easter: dark
            ? (0xB0A9C3, 0x716587, 0x9486A9, 0x19151F)
            : (0xF1E8F5, 0xAD94BC, 0xD3BFDD, 0xFCF7FD)
        case .valentines: dark
            ? (0xAF8491, 0x775361, 0x9C6A7C, 0x211318)
            : (0xF9E3E8, 0xC593A2, 0xDEB2C0, 0xFFF6F8)
        case .lunarNewYear: dark
            ? (0x552C35, 0xA9766D, 0xA9775A, 0x211216)
            : (0xF5D8D1, 0xB77F6A, 0xCDA367, 0xFFF5EF)
        case .space: (0x202F50, 0x5F739B, 0x4D628C, dark ? 0x0D1423 : 0xF0F3FA)
        case .nature: dark
            ? (0xA1B098, 0x657655, 0x859675, 0x151B12)
            : (0xE5ECDC, 0x98AA83, 0xBBCBAA, 0xF5F8F0)
        case .pets: dark
            ? (0xB7A38B, 0x78644E, 0x9B8468, 0x1D1812)
            : (0xF0E4D1, 0xB5A184, 0xD3BD9A, 0xFAF7F1)
        case .ocean: dark
            ? (0x759EA5, 0x3E6C77, 0x5D8993, 0x0E1B20)
            : (0xDCEEF1, 0x85AFBA, 0xACCDD5, 0xF1F9FA)
        }
        return .init(
            theme: theme,
            boardSurface: Color(hex: colors.surface),
            boardGrid: Color(hex: colors.grid),
            boardEdge: Color(hex: colors.edge),
            stoneBorder: .black.opacity(0.32),
            background: Color(hex: colors.background),
            winningGold: Color(hex: dark || theme == .space ? 0xFFE078 : 0x93621C)
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
