import XCTest
@testable import terminalmanager

@MainActor
final class GUISmokeTests: TempConfigTestCase {
    func testSmokeTestRunnerPassesInProcess() throws {
        try SmokeTestRunner.runAll()
    }

    func testMainWindowViewModelFlows() {
        let appState = AppState(configStore: ConfigStore())
        appState.bootstrap()
        for tab in appState.tabs {
            appState.closeTab(tab.id)
        }

        let first = appState.openLocalTab()
        let second = appState.openLocalTab()
        XCTAssertEqual(appState.stripTabs.count, 2)

        appState.selectedTabID = first
        appState.selectNextTab()
        XCTAssertEqual(appState.selectedTabID, second)

        appState.renameTab(first, title: "Renamed")
        XCTAssertEqual(appState.tabs.first(where: { $0.id == first })?.title, "Renamed")

        appState.showFindBar = true
        XCTAssertTrue(appState.showFindBar)

        appState.closeTab(first)
        appState.closeTab(second)
        XCTAssertTrue(appState.tabs.isEmpty)
    }
}
