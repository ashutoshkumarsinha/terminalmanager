import XCTest
@testable import terminalmanager

final class TabLifecyclePolicyTests: XCTestCase {
    func testHibernatesOnlyInvisibleRunningTabsAfterTimeout() {
        let tabA = UUID()
        let tabB = UUID()
        let tabC = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastActive: [UUID: Date] = [
            tabA: now.addingTimeInterval(-3600),
            tabB: now.addingTimeInterval(-120),
            tabC: now.addingTimeInterval(-3600)
        ]

        let result = TabLifecyclePolicy.tabIDsToHibernate(
            tabIDs: [tabA, tabB, tabC],
            visibleTabIDs: [tabB],
            runningTabIDs: [tabA, tabB, tabC],
            lastActiveAt: lastActive,
            now: now,
            inactivityMinutes: 30
        )

        XCTAssertEqual(Set(result), [tabA, tabC])
    }

    func testDoesNotHibernateWhenDisabled() {
        let tabID = UUID()
        let now = Date()
        let result = TabLifecyclePolicy.tabIDsToHibernate(
            tabIDs: [tabID],
            visibleTabIDs: [],
            runningTabIDs: [tabID],
            lastActiveAt: [tabID: now.addingTimeInterval(-7200)],
            now: now,
            inactivityMinutes: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testDoesNotHibernateVisibleTabs() {
        let tabID = UUID()
        let now = Date()
        let result = TabLifecyclePolicy.tabIDsToHibernate(
            tabIDs: [tabID],
            visibleTabIDs: [tabID],
            runningTabIDs: [tabID],
            lastActiveAt: [tabID: now.addingTimeInterval(-7200)],
            now: now,
            inactivityMinutes: 30
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testMergedVisibleTabIDsIncludesMainAndDetached() {
        let main = UUID()
        let detached = UUID()
        let merged = TabLifecyclePolicy.mergedVisibleTabIDs(
            mainWindow: [main],
            detached: [detached]
        )
        XCTAssertEqual(merged, [main, detached])
    }
}
