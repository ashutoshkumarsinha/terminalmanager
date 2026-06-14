import XCTest
@testable import terminalmanager

final class LaunchStateStoreTests: TempConfigTestCase {
    func testSaveLoadAndClear() throws {
        let profileA = UUID()
        let profileB = UUID()
        let layout = SplitLayoutNode.split(
            .horizontal,
            .leaf(tabID: profileA),
            .leaf(tabID: profileB),
            ratio: 0.6
        )

        let state = LaunchState(
            tabProfileIDs: [profileA, profileB],
            selectedTabProfileID: profileA,
            splitLayouts: [profileA: layout]
        )

        try LaunchStateStore.save(state)
        let loaded = LaunchStateStore.load()
        XCTAssertEqual(loaded, state)

        LaunchStateStore.clear()
        XCTAssertNil(LaunchStateStore.load())
    }

    func testLoadReturnsNilWhenMissing() {
        LaunchStateStore.clear()
        XCTAssertNil(LaunchStateStore.load())
    }
}
