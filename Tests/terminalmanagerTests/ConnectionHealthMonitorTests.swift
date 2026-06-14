import XCTest
@testable import terminalmanager

@MainActor
final class ConnectionHealthMonitorTests: XCTestCase {
    func testStaleWhenNoRecentOutput() {
        let monitor = ConnectionHealthMonitor()
        monitor.configure(staleAfterMinutes: 5)
        let tabID = UUID()
        monitor.touchTab(tabID, at: Date(timeIntervalSinceNow: -600))
        let health = monitor.health(for: tabID, isRunning: true, now: Date())
        XCTAssertEqual(health, .stale)
    }

    func testHealthyWhenRecentOutput() {
        let monitor = ConnectionHealthMonitor()
        monitor.configure(staleAfterMinutes: 5)
        let tabID = UUID()
        monitor.recordOutput(tabID: tabID)
        let health = monitor.health(for: tabID, isRunning: true)
        XCTAssertEqual(health, .healthy)
    }

    func testUnknownWhenNotRunningAndNoOutput() {
        let monitor = ConnectionHealthMonitor()
        let health = monitor.health(for: UUID(), isRunning: false)
        XCTAssertEqual(health, .unknown)
    }

    func testHealthyWhenRecentOutputEvenIfNotRunning() {
        let monitor = ConnectionHealthMonitor()
        monitor.configure(staleAfterMinutes: 5)
        let tabID = UUID()
        monitor.recordOutput(tabID: tabID)
        let health = monitor.health(for: tabID, isRunning: false)
        XCTAssertEqual(health, .healthy)
    }
}
