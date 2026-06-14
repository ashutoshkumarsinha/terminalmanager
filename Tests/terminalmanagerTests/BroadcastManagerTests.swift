import XCTest
@testable import terminalmanager

@MainActor
final class BroadcastManagerTests: XCTestCase {
    func testNormalizedPayloadRejectsEmptyInput() {
        XCTAssertNil(BroadcastManager.normalizedPayload(from: ""))
        XCTAssertNil(BroadcastManager.normalizedPayload(from: "   \n  "))
    }

    func testNormalizedPayloadPreservesMultilineCommands() {
        XCTAssertEqual(
            BroadcastManager.normalizedPayload(from: "uptime\nwhoami"),
            "uptime\nwhoami\n"
        )
    }

    func testRecordCommandDedupesAndLimitsHistory() {
        let manager = BroadcastManager()
        manager.recordCommand("first")
        manager.recordCommand("second")
        manager.recordCommand("first")

        XCTAssertEqual(manager.commandHistory, ["first", "second"])

        for index in 0 ..< 25 {
            manager.recordCommand("cmd-\(index)")
        }
        XCTAssertEqual(manager.commandHistory.count, 20)
        XCTAssertEqual(manager.commandHistory.first, "cmd-24")
    }

    func testSendDispatchesToRegisteredHandlers() {
        let manager = BroadcastManager()
        let tabA = UUID()
        let tabB = UUID()
        var receivedA: [String] = []
        var receivedB: [String] = []

        manager.register(tabID: tabA) { receivedA.append($0) }
        manager.register(tabID: tabB) { receivedB.append($0) }
        manager.commandText = "echo hi"

        manager.send(to: [tabA, tabB])
        XCTAssertEqual(receivedA, ["echo hi\n"])
        XCTAssertEqual(receivedB, ["echo hi\n"])
        XCTAssertEqual(manager.commandText, "")
        XCTAssertEqual(manager.commandHistory.first, "echo hi")
    }

    func testSendSkipsIneligibleTabs() {
        let manager = BroadcastManager()
        let tabA = UUID()
        let tabB = UUID()
        var receivedA: [String] = []
        var receivedB: [String] = []

        manager.register(tabID: tabA) { receivedA.append($0) }
        manager.register(tabID: tabB) { receivedB.append($0) }
        manager.commandText = "echo hi"

        manager.send(to: [tabA, tabB], eligibleTabIDs: [tabA])
        XCTAssertEqual(receivedA, ["echo hi\n"])
        XCTAssertTrue(receivedB.isEmpty)
    }

    func testPresetsApplyAndRemove() {
        let manager = BroadcastManager()
        manager.setPreset("status", command: "systemctl status nginx")
        manager.applyPreset("status")
        XCTAssertEqual(manager.commandText, "systemctl status nginx")

        manager.removePreset("status")
        manager.commandText = ""
        manager.applyPreset("status")
        XCTAssertEqual(manager.commandText, "")
    }
}
