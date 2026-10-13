import XCTest

final class ThemeSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testThemeIsOptInThroughSettingsAndSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings-theme"].exists)
        XCTAssertFalse(app.buttons["theme-option-halloween"].exists)

        openThemes(in: app)
        assertSelected("standard", in: app)
        attachScreenshot(named: "Themes - Standard default", in: app)
        let halloween = app.buttons["theme-option-halloween"]
        XCTAssertTrue(halloween.waitForExistence(timeout: 2))
        halloween.tap()
        assertSelected("halloween", in: app)
        closeSettings(in: app)
        assertVisiblePlayerName("Pumpkin", in: app)
        attachScreenshot(named: "Halloween gameplay", in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.otherElements["game-board"].waitForExistence(timeout: 5))
        assertVisiblePlayerName("Pumpkin", in: app)
        openThemes(in: app)
        assertSelected("halloween", in: app)

        app.buttons["theme-option-standard"].tap()
        assertSelected("standard", in: app)
        closeSettings(in: app)
        assertVisiblePlayerName("Black", in: app)
        XCTAssertFalse(app.buttons["settings-theme"].exists)
        XCTAssertFalse(app.buttons["theme-option-standard"].exists)
    }

    @MainActor
    private func openThemes(in app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let themes = app.buttons["settings-theme"]
        XCTAssertTrue(themes.waitForExistence(timeout: 3))
        themes.tap()
        XCTAssertTrue(app.navigationBars["Themes"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        app.navigationBars["Themes"].buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.navigationBars["Settings"].buttons["Done"].tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Settings"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
    }

    @MainActor
    private func assertSelected(_ theme: String, in app: XCUIApplication) {
        let option = app.buttons["theme-option-\(theme)"]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: option
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
    }

    @MainActor
    private func assertVisiblePlayerName(_ name: String, in app: XCUIApplication) {
        let player = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 3), "The gameplay turn display should use \(name)")
    }

    @MainActor
    private func attachScreenshot(named name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
