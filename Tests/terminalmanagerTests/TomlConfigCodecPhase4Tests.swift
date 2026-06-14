import XCTest
@testable import terminalmanager

final class TomlConfigCodecPhase4Tests: XCTestCase {
    func testDecodePhase4PerformanceFields() throws {
        let toml = """
        [app]
        version = 1

        [ui]
        show_sidebar = true
        broadcast_enabled = true

        [sessions]
        file = "sessions.json"

        [performance]
        config_schema_version = 2
        copy_on_select = true
        paste_on_middle_click = false
        stale_tab_minutes = 7
        session_recording_enabled = true
        check_for_updates = false
        update_repository = "acme/widget"

        [performance.ansi_palette]
        red = "#FF0000"
        green = "#00FF00"

        [[bastions]]
        id = "11111111-1111-1111-1111-111111111111"
        name = "Edge"
        host = "edge.example.com"
        username = "ops"
        port = 2222

        [[shortcuts]]
        id = "newTab"
        key = "t"
        modifiers = ["command"]
        """

        let settings = try TomlConfigCodec.decode(fromString: toml)
        XCTAssertEqual(settings.configSchemaVersion, 2)
        XCTAssertTrue(settings.copyOnSelect)
        XCTAssertFalse(settings.pasteOnMiddleClick)
        XCTAssertEqual(settings.staleTabMinutes, 7)
        XCTAssertTrue(settings.sessionRecordingEnabled)
        XCTAssertFalse(settings.checkForUpdates)
        XCTAssertEqual(settings.updateRepository, "acme/widget")
        XCTAssertEqual(settings.ansiPalette?.red, "#FF0000")
        XCTAssertEqual(settings.bastionProfiles.count, 1)
        XCTAssertEqual(settings.bastionProfiles[0].port, 2222)
    }

    func testEncodeDecodeRoundTripPhase4Fields() throws {
        var settings = AppSettings.defaults
        settings.copyOnSelect = true
        settings.pasteOnMiddleClick = false
        settings.staleTabMinutes = 12
        settings.sessionRecordingEnabled = true
        settings.checkForUpdates = false
        settings.updateRepository = "org/repo"
        settings.bastionProfiles = [
            BastionProfile(name: "Jump", host: "jump.local", username: "admin", port: 22)
        ]
        settings.ansiPalette = ANSIPalette(
            black: "#010101",
            red: "#020202",
            green: "#030303",
            yellow: "#040404",
            blue: "#050505",
            magenta: "#060606",
            cyan: "#070707",
            white: "#080808"
        )

        let encoded = try TomlConfigCodec.encode(settings)
        let decoded = try TomlConfigCodec.decode(fromString: encoded)
        XCTAssertEqual(decoded.copyOnSelect, true)
        XCTAssertEqual(decoded.pasteOnMiddleClick, false)
        XCTAssertEqual(decoded.staleTabMinutes, 12)
        XCTAssertEqual(decoded.sessionRecordingEnabled, true)
        XCTAssertEqual(decoded.bastionProfiles.first?.host, "jump.local")
        XCTAssertEqual(decoded.ansiPalette?.cyan, "#070707")
    }
}
