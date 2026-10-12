#if DEBUG
import Foundation
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Deterministic local data for UI automation; normal launches never enter this path.
@MainActor
enum UITestFixtures {
    private static var artifactDirectory: URL?
    struct Dependencies {
        let game: GameState
        let preferences: PreferencesStore
        let archive: ModelContainer
    }

    static func makeIfRequested() -> Dependencies? {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--ui-testing") else { return nil }
        let runID = process.environment["UI_TEST_RUN_ID"] ?? UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustGomokuUITests", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        artifactDirectory = directory.appendingPathComponent("artifacts", isDirectory: true)
        let store = ActiveSessionStore(fileURL: directory.appendingPathComponent("active-session.json"))
        if store.load() == nil {
            if process.arguments.contains("--ui-testing-draw") { store.save(draw()) }
            else if process.arguments.contains("--ui-testing-win") { store.save(win(boardSize: 9)) }
        }

        let defaults = UserDefaults(suiteName: "com.xjrmh.gomoku.ui-testing.\(runID)")!
        let preferences = PreferencesStore(defaults: defaults, cloud: nil)
        let schema = Schema([ArchivedGame.self])
        let configuration = ModelConfiguration(
            "UITestArchive", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        let archive = try! ModelContainer(for: schema, configurations: configuration)
        if process.arguments.contains("--ui-testing-history") {
            let newestDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
            for index in 0..<40 {
                let session = index == 0 ? draw() : win(boardSize: [9, 15, 19, 25][(index - 1) % 4])
                archive.mainContext.insert(ArchivedGame(session: session, completedAt: newestDate.addingTimeInterval(-Double(index) * 86_400)))
            }
            try! archive.mainContext.save()
        }
        return Dependencies(game: GameState(sessionStore: store), preferences: preferences, archive: archive)
    }

    private static func win(boardSize: Int) -> GameSession {
        var session = GameSession(configuration: .init(boardSize: boardSize))
        for column in 0..<5 {
            precondition(session.place(at: .init(r: 0, c: column), controller: .human, now: timestamp(column * 2)))
            if column < 4 {
                precondition(session.place(at: .init(r: 1, c: column), controller: .human, now: timestamp(column * 2 + 1)))
            }
        }
        precondition(session.isValid)
        return session
    }

    private static func draw() -> GameSession {
        let rows = [
            [1, 1, 2, 2, 1], [2, 2, 1, 1, 2], [1, 1, 2, 2, 1],
            [2, 2, 1, 1, 2], [1, 2, 1, 2, 1],
        ]
        var black: [Position] = []
        var white: [Position] = []
        for row in 0..<5 {
            for column in 0..<5 {
                if rows[row][column] == 1 { black.append(.init(r: row, c: column)) }
                else { white.append(.init(r: row, c: column)) }
            }
        }
        var session = GameSession(configuration: .init(boardSize: 5))
        for index in 0..<13 {
            precondition(session.place(at: black[index], controller: .human, now: timestamp(index * 2)))
            if index < 12 {
                precondition(session.place(at: white[index], controller: .human, now: timestamp(index * 2 + 1)))
            }
        }
        precondition(session.outcome == .draw && session.isValid)
        return session
    }

    private static func timestamp(_ seconds: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(seconds))
    }

    static func recordShareCard(_ payload: SharePayload, colorScheme: ColorScheme) {
        guard let artifactDirectory else { return }
        try? FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let appearance = colorScheme == .dark ? "dark" : "light"
        try? payload.pngData.write(to: artifactDirectory.appendingPathComponent("share-\(appearance).png"), options: .atomic)
    }

    #if os(iOS)
    static func recordScrollMetrics() {
        guard let artifactDirectory else { return }

        func size(_ value: CGSize) -> [String: Double] {
            ["width": Double(value.width), "height": Double(value.height)]
        }
        func point(_ value: CGPoint) -> [String: Double] {
            ["x": Double(value.x), "y": Double(value.y)]
        }
        func rect(_ value: CGRect) -> [String: Double] {
            ["x": Double(value.minX), "y": Double(value.minY),
             "width": Double(value.width), "height": Double(value.height)]
        }
        func insets(_ value: UIEdgeInsets) -> [String: Double] {
            ["top": Double(value.top), "left": Double(value.left),
             "bottom": Double(value.bottom), "right": Double(value.right)]
        }
        func scrollViews(in view: UIView, window: UIWindow, path: String) -> [[String: Any]] {
            var result: [[String: Any]] = []
            if let scroll = view as? UIScrollView {
                result.append([
                    "path": path,
                    "class": String(describing: type(of: scroll)),
                    "frameInWindow": rect(scroll.convert(scroll.bounds, to: window)),
                    "boundsSize": size(scroll.bounds.size),
                    "contentSize": size(scroll.contentSize),
                    "contentOffset": point(scroll.contentOffset),
                    "isScrollEnabled": scroll.isScrollEnabled,
                    "isHidden": scroll.isHidden,
                    "isUserInteractionEnabled": scroll.isUserInteractionEnabled,
                    "isDragging": scroll.isDragging,
                    "isTracking": scroll.isTracking,
                    "isDecelerating": scroll.isDecelerating,
                    "adjustedContentInset": insets(scroll.adjustedContentInset),
                    "contentInset": insets(scroll.contentInset),
                ])
            }
            for (index, child) in view.subviews.enumerated() {
                let childPath = "\(path)/\(String(describing: type(of: child)))[\(index)]"
                result.append(contentsOf: scrollViews(in: child, window: window, path: childPath))
            }
            return result
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var windows: [[String: Any]] = []
        for scene in scenes {
            for (index, window) in scene.windows.enumerated() {
                windows.append([
                    "sceneID": scene.session.persistentIdentifier,
                    "windowIndex": index,
                    "isKeyWindow": window.isKeyWindow,
                    "isHidden": window.isHidden,
                    "boundsSize": size(window.bounds.size),
                    "scrollViews": scrollViews(in: window, window: window, path: "UIWindow[\(index)]"),
                ])
            }
        }
        let metrics: [String: Any] = [
            "recordedAt": ISO8601DateFormatter().string(from: .now),
            "windows": windows,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        try? data.write(to: artifactDirectory.appendingPathComponent("scroll-metrics.json"), options: .atomic)
    }
    #endif
}
#endif
