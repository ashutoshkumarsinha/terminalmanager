import XCTest
@testable import terminalmanager

final class TomlConfigCodecTests: XCTestCase {
    func testDecodeNewTerminalAndLoggingSections() throws {
        let toml = """
        [app]
        version = 1
        single_instance = false

        [window]
        restore_position = true

        [terminal]
        font_name = "SF Mono"
        font_size = 11.0
        theme = "dark"
        restore_tabs_on_launch = true
        auto_reconnect = false

        [ui]
        show_sidebar = true
        broadcast_enabled = true

        [sessions]
        file = "sessions.json"
        sync_path = "/Users/me/sync/sessions.json"

        [logging]
        level = "debug"
        log_terminal_io = false
        terminal_io_max_mb = 25

        [performance]
        hibernate_inactive_tabs_minutes = 15
        terminal_io_metadata_only = true

        [[shortcuts]]
        id = "newTab"
        key = "t"
        modifiers = ["command"]
        """

        let settings = try TomlConfigCodec.decode(fromString: toml)
        XCTAssertEqual(settings.terminalFontName, "SF Mono")
        XCTAssertEqual(settings.terminalFontSize, 11)
        XCTAssertEqual(settings.terminalTheme, .dark)
        XCTAssertTrue(settings.restoreTabsOnLaunch)
        XCTAssertFalse(settings.autoReconnect)
        XCTAssertEqual(settings.syncSessionsPath, "/Users/me/sync/sessions.json")
        XCTAssertEqual(settings.logLevel, .debug)
        XCTAssertFalse(settings.logTerminalIO)
        XCTAssertEqual(settings.terminalIOMaxMB, 25)
        XCTAssertEqual(settings.hibernateInactiveTabsMinutes, 15)
        XCTAssertTrue(settings.terminalIOMetadataOnly)
    }

    func testEncodeDecodeRoundTripPreservesNewFields() throws {
        var settings = AppSettings.defaults
        settings.terminalFontName = "Menlo"
        settings.terminalFontSize = 13
        settings.terminalTheme = .light
        settings.restoreTabsOnLaunch = true
        settings.autoReconnect = false
        settings.logTerminalIO = false
        settings.terminalIOMaxMB = 100
        settings.syncSessionsPath = "~/sync/sessions.json"
        settings.sessionTemplates = [
            SessionTemplate(
                name: "Default SSH",
                protocolType: .ssh,
                username: "deploy",
                port: 22,
                proxyJump: "bastion.example.com",
                sshExtraOptions: "-o StrictHostKeyChecking=no",
                tagColor: "green"
            )
        ]

        let encoded = try TomlConfigCodec.encode(settings)
        let decoded = try TomlConfigCodec.decode(fromString: encoded)

        XCTAssertEqual(decoded.terminalFontName, settings.terminalFontName)
        XCTAssertEqual(decoded.terminalFontSize, settings.terminalFontSize)
        XCTAssertEqual(decoded.terminalTheme, settings.terminalTheme)
        XCTAssertEqual(decoded.restoreTabsOnLaunch, settings.restoreTabsOnLaunch)
        XCTAssertEqual(decoded.autoReconnect, settings.autoReconnect)
        XCTAssertEqual(decoded.logTerminalIO, settings.logTerminalIO)
        XCTAssertEqual(decoded.terminalIOMaxMB, settings.terminalIOMaxMB)
        XCTAssertEqual(decoded.syncSessionsPath, settings.syncSessionsPath)
        XCTAssertEqual(decoded.sessionTemplates.count, 1)
        XCTAssertEqual(decoded.sessionTemplates[0].name, "Default SSH")
        XCTAssertEqual(decoded.sessionTemplates[0].proxyJump, "bastion.example.com")
        XCTAssertEqual(decoded.sessionTemplates[0].tagColor, "green")
    }
}
