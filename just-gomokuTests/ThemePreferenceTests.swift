import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import just_gomoku

@MainActor
final class ThemePreferenceTests: XCTestCase {
    func testLegacyPreferencesKeepExistingSettingsAndUseStandardTheme() throws {
        let expected = customizedPayload()
        var legacy = try encodedObject(expected)
        legacy.removeValue(forKey: "theme")

        let restored = try decode(legacy)

        XCTAssertEqual(restored.theme, .standard)
        XCTAssertEqual(restored, expected, "Adding a theme must preserve previously saved settings")
    }

    func testUnknownThemeFallsBackWithoutDiscardingExistingPreferences() throws {
        let expected = customizedPayload()
        var future = try encodedObject(expected)
        future["theme"] = "future-holiday"

        let restored = try decode(future)

        XCTAssertEqual(restored.theme, .standard)
        XCTAssertEqual(restored, expected, "An unfamiliar theme must not reset unrelated preferences")
    }

    func testThemeSelectionAndResetPersistAcrossStores() throws {
        let suite = "JustGomokuThemeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = PreferencesStore(defaults: defaults, cloud: nil)
        XCTAssertEqual(preferences.theme, .standard)
        preferences.appearance = .dark
        preferences.hapticsEnabled = false
        preferences.theme = .halloween

        let restored = PreferencesStore(defaults: defaults, cloud: nil)
        XCTAssertEqual(restored.theme, .halloween)
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertFalse(restored.hapticsEnabled)

        restored.theme = .standard
        let reset = PreferencesStore(defaults: defaults, cloud: nil)
        XCTAssertEqual(reset.theme, .standard)
        XCTAssertEqual(reset.appearance, .dark)
        XCTAssertFalse(reset.hapticsEnabled)
    }

    func testEveryThemeExportsFinishedGameInLightAndDarkAppearance() throws {
        let session = finishedGame()
        XCTAssertTrue(session.isValid)
        XCTAssertEqual(session.outcome.winner, .black)

        for theme in BoardTheme.allCases {
            for scheme in [ColorScheme.light, .dark] {
                try autoreleasepool {
                    let appearance = scheme == .dark ? "dark" : "light"
                    let palette = GomokuPalette.resolve(scheme, theme: theme)
                    let payload = try XCTUnwrap(
                        ShareCardRenderer.render(session: session, palette: palette, colorScheme: scheme),
                        "\(theme.title) should export in \(appearance) appearance"
                    )
                    XCTAssertEqual(payload.title, "\(theme.playerName(.black)) wins · 9 moves")
                    XCTAssertFalse(payload.pngData.isEmpty)
                    XCTAssertEqual(Array(payload.pngData.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
                    let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(payload.pngData as CFData, nil))
                    XCTAssertNotNil(CGImageSourceCreateImageAtIndex(imageSource, 0, nil), "The exported PNG must decode")

                    let attachment = XCTAttachment(data: payload.pngData, uniformTypeIdentifier: UTType.png.identifier)
                    attachment.name = "Share card - \(theme.rawValue) - \(appearance)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func finishedGame() -> GameSession {
        var session = GameSession(configuration: .init(mode: .pvp, boardSize: 9))
        for column in 0..<5 {
            XCTAssertTrue(session.place(
                at: .init(r: 4, c: column + 2), controller: .human,
                now: Date(timeIntervalSinceReferenceDate: Double(column * 2))
            ))
            if column < 4 {
                XCTAssertTrue(session.place(
                    at: .init(r: 5, c: column + 2), controller: .human,
                    now: Date(timeIntervalSinceReferenceDate: Double(column * 2 + 1))
                ))
            }
        }
        return session
    }

    private func customizedPayload() -> PreferencePayload {
        var payload = PreferencePayload()
        payload.modifiedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        payload.appearance = .dark
        payload.hapticsEnabled = false
        payload.defaultMode = .ai
        payload.boardSize = 19
        payload.difficulty = .hard
        payload.humanSide = .black
        payload.didShowPrecisionCoachMark = true
        return payload
    }

    private func encodedObject(_ payload: PreferencePayload) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> PreferencePayload {
        try JSONDecoder().decode(PreferencePayload.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
