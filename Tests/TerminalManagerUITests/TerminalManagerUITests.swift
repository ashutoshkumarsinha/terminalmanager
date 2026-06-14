import XCTest

final class TerminalManagerUITests: XCTestCase {
    private var configDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        configDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm-uitest-\(UUID().uuidString)", isDirectory: true)
        try UITestConfigBootstrap.writeMinimalConfig(at: configDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: configDirectory)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TERMINALMANAGER_CONFIG"] = configDirectory.path
        app.launchArguments = ["-uitest"]
        app.launch()
        return app
    }

    private func sidebarSearchField(in app: XCUIApplication) -> XCUIElement {
        let byIdentifier = app.textFields["session.sidebar.search"]
        if byIdentifier.exists { return byIdentifier }
        let byLabel = app.textFields["Search sessions"]
        if byLabel.exists { return byLabel }
        return app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'Search sessions'")
        ).firstMatch
    }

    func testLaunchShowsMainWindowAndSidebarSearch() throws {
        let app = launchApp()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let sidebarSearch = sidebarSearchField(in: app)
        XCTAssertTrue(sidebarSearch.waitForExistence(timeout: 10))
    }

    func testNewTabButtonAddsTabStripEntry() throws {
        let app = launchApp()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let newTab = app.buttons["tab.strip.new"]
        if !newTab.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.buttons["New Tab"].waitForExistence(timeout: 5))
        }
        (newTab.exists ? newTab : app.buttons["New Tab"]).click()

        let localTab = app.buttons["tab.strip.chip.Local"]
        XCTAssertTrue(localTab.waitForExistence(timeout: 5))
    }

    func testSidebarSearchFiltersPlaceholder() throws {
        let app = launchApp()

        let sidebarSearch = sidebarSearchField(in: app)
        XCTAssertTrue(sidebarSearch.waitForExistence(timeout: 15))
        sidebarSearch.click()
        sidebarSearch.typeText("nonexistent-host-xyz")
        let value = sidebarSearch.value as? String ?? ""
        XCTAssertTrue(value.contains("nonexistent-host-xyz"))
    }
}

enum UITestConfigBootstrap {
    static func writeMinimalConfig(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = """
        [app]
        version = 1
        single_instance = false

        [window]
        restore_position = false

        [terminal]
        restore_tabs_on_launch = false
        auto_reconnect = false

        [ui]
        show_sidebar = true
        show_command_bar = false
        show_tooltips = false
        broadcast_enabled = false
        confirm_on_exit = false

        [sessions]
        file = "sessions.json"

        [logging]
        level = "error"
        log_terminal_io = false

        [performance]
        defer_sessions_load = true
        check_for_updates = false
        session_recording_enabled = false
        """
        try config.write(
            to: directory.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        let sessions = """
        {"version":1,"sessionTree":[]}
        """
        try sessions.write(
            to: directory.appendingPathComponent("sessions.json"),
            atomically: true,
            encoding: .utf8
        )
    }
}
