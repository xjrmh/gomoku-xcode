import XCTest
@testable import just_gomoku

final class ActiveSessionStoreTests: XCTestCase {
    func testSaveLoadAndClear() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustGomokuTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        var session = GameSession(configuration: .init(mode: .pvp, boardSize: 9))
        XCTAssertTrue(session.place(at: .init(r: 4, c: 4), controller: .human))

        store.save(session)
        XCTAssertEqual(store.load(), session)

        store.clear()
        XCTAssertNil(store.load())
    }

    func testCorruptSessionFailsClosed() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustGomokuCorrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not-json".utf8).write(to: file)

        XCTAssertNil(ActiveSessionStore(fileURL: file).load())
    }
}
