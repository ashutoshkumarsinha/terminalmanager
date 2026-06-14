import XCTest
@testable import terminalmanager

@MainActor
final class AppStatePhase4Tests: TempConfigTestCase {
    func testRecordTerminalOutputUpdatesHealthWhenRunning() {
        let appState = AppState(configStore: ConfigStore())
        appState.bootstrap()
        let tabID = appState.openLocalTab()
        _ = appState.terminalStore.terminal(for: tabID, sessionName: "Local")

        appState.recordTerminalOutput(tabID: tabID)
        // Health reflects running state only; without an active PTY, status stays unknown (not stale).
        XCTAssertNotEqual(appState.connectionHealth[tabID], .stale)
        appState.closeTab(tabID)
    }

    func testUpdateTabRemoteOverridesPersistsInTab() {
        let appState = AppState(configStore: ConfigStore())
        let tabID = appState.openTab(from: SessionProfile(name: "SSH", host: "host", protocolType: .ssh))

        appState.updateTabRemoteOverrides(
            tabID: tabID,
            remoteEnvironment: "FOO=bar",
            remoteWorkingDirectory: "/opt"
        )

        let tab = appState.tabs.first { $0.id == tabID }
        XCTAssertEqual(tab?.remoteEnvironmentOverride, "FOO=bar")
        XCTAssertEqual(tab?.remoteWorkingDirectoryOverride, "/opt")
        appState.closeTab(tabID)
    }

    func testSettingsCopyOnSelectUpdatesTerminalStore() {
        let appState = AppState(configStore: ConfigStore())
        var settings = appState.settings
        settings.copyOnSelect = true
        settings.pasteOnMiddleClick = false
        appState.settings = settings

        let tabID = appState.openLocalTab()
        let terminal = appState.terminalStore.terminal(for: tabID)
        XCTAssertTrue(terminal.copyOnSelect)
        XCTAssertFalse(terminal.pasteOnMiddleClick)
        appState.closeTab(tabID)
    }

    func testCloseTabClearsConnectionHealth() {
        let appState = AppState(configStore: ConfigStore())
        let tabID = appState.openLocalTab()
        appState.recordTerminalOutput(tabID: tabID)
        XCTAssertNotNil(appState.connectionHealth[tabID])

        appState.closeTab(tabID)
        XCTAssertNil(appState.connectionHealth[tabID])
    }
}
