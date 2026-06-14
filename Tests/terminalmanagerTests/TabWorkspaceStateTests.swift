import XCTest
@testable import terminalmanager

@MainActor
final class TabWorkspaceStateTests: XCTestCase {
    func testConnectionHealthUpdates() {
        let workspace = TabWorkspaceState()
        let tabID = UUID()

        workspace.setConnectionHealth(.healthy, for: tabID)
        XCTAssertEqual(workspace.connectionHealth[tabID], .healthy)

        workspace.setConnectionHealth(.healthy, for: tabID)
        workspace.setConnectionHealth(.stale, for: tabID)
        XCTAssertEqual(workspace.connectionHealth[tabID], .stale)

        workspace.removeConnectionHealth(for: tabID)
        XCTAssertNil(workspace.connectionHealth[tabID])
    }

    func testStripTabsExcludesSplitPanes() {
        let workspace = TabWorkspaceState()
        let anchor = TerminalTab(title: "Main", profile: SessionProfile(name: "Main", protocolType: .local))
        let pane = TerminalTab(title: "Pane", profile: SessionProfile(name: "Pane", protocolType: .local), isSplitPane: true)
        workspace.tabs = [anchor, pane]
        XCTAssertEqual(workspace.stripTabs.count, 1)
        XCTAssertEqual(workspace.stripTabs[0].id, anchor.id)
    }

    func testStripTabSelectionWithSplitLayout() {
        let workspace = TabWorkspaceState()
        let anchor = TerminalTab(title: "Main", profile: SessionProfile(name: "Main", protocolType: .local))
        let pane = TerminalTab(title: "Pane", profile: SessionProfile(name: "Pane", protocolType: .local), isSplitPane: true)
        workspace.tabs = [anchor, pane]
        workspace.selectedTabID = pane.id
        let split = SplitLayoutNode.split(.horizontal, .leaf(tabID: anchor.id), .leaf(tabID: pane.id))
        workspace.setSplitLayout(split, anchor: anchor.id)
        XCTAssertEqual(workspace.stripTabID(for: pane.id), anchor.id)
        XCTAssertTrue(workspace.isStripTabSelected(anchor.id))
    }
}
