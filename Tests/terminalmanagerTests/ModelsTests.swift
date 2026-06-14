import XCTest
@testable import terminalmanager

final class SessionProfileCodingTests: XCTestCase {
    func testEncodesNewSSHFields() throws {
        let profile = SessionProfile(
            name: "Prod",
            host: "prod.example.com",
            username: "deploy",
            protocolType: .ssh,
            sshAuthMethod: .agent,
            tagColor: "#FF5500",
            proxyJump: "bastion.example.com",
            sshExtraOptions: "-o ForwardAgent=yes"
        )

        let data = try JSONEncoder().encode(profile)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("tagColor"))
        XCTAssertTrue(json.contains("proxyJump"))
        XCTAssertTrue(json.contains("sshExtraOptions"))
        XCTAssertTrue(json.contains("bastion.example.com"))
    }

    func testDecodesSSH2ProtocolAlias() throws {
        let json = """
        {
          "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
          "name": "Legacy",
          "host": "host",
          "username": "user",
          "protocolType": "ssh2"
        }
        """.data(using: .utf8)!

        struct Wrapper: Decodable {
            var id: UUID
            var name: String
            var host: String
            var username: String
            var protocolType: ConnectionProtocol
        }

        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(decoded.protocolType, .ssh)
    }
}

final class LaunchStateCodingTests: XCTestCase {
    func testLaunchStateRoundTripJSON() throws {
        let tabA = UUID()
        let tabB = UUID()
        let state = LaunchState(
            tabProfileIDs: [tabA, tabB],
            selectedTabProfileID: tabA,
            splitLayouts: [
                tabA: SplitLayoutNode.split(.horizontal, .leaf(tabID: tabA), .leaf(tabID: tabB))
            ]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(LaunchState.self, from: data)
        XCTAssertEqual(decoded, state)
    }
}

final class TabSessionStateTests: XCTestCase {
    func testTabSessionStateRawValues() {
        XCTAssertEqual(TabSessionState.idle.rawValue, "idle")
        XCTAssertEqual(TabSessionState.running.rawValue, "running")
        XCTAssertEqual(TabSessionState.exited.rawValue, "exited")
        XCTAssertEqual(TabSessionState.hibernated.rawValue, "hibernated")
    }
}
