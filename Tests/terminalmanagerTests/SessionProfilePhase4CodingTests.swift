import XCTest
@testable import terminalmanager

final class SessionProfilePhase4CodingTests: XCTestCase {
    func testEncodesPhase4Fields() throws {
        let profile = SessionProfile(
            name: "Prod",
            host: "prod.example.com",
            protocolType: .ssh,
            notes: "runbook",
            notesInKeychain: true,
            remoteEnvironment: "ENV=1",
            remoteWorkingDirectory: "/srv",
            bastionProfileID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
            sftpBookmarks: ["/var/log", "/home/deploy"]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(SessionProfile.self, from: data)
        XCTAssertTrue(decoded.notesInKeychain)
        XCTAssertEqual(decoded.remoteEnvironment, "ENV=1")
        XCTAssertEqual(decoded.remoteWorkingDirectory, "/srv")
        XCTAssertEqual(decoded.bastionProfileID?.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(decoded.sftpBookmarks, ["/var/log", "/home/deploy"])
    }

    func testDecodesMissingPhase4FieldsWithDefaults() throws {
        let json = """
        {
          "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
          "name": "Legacy",
          "host": "host",
          "username": "user",
          "protocolType": "ssh"
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(SessionProfile.self, from: json)
        XCTAssertFalse(profile.notesInKeychain)
        XCTAssertNil(profile.remoteEnvironment)
        XCTAssertNil(profile.bastionProfileID)
        XCTAssertTrue(profile.sftpBookmarks.isEmpty)
    }

    func testTerminalTabStoresRemoteOverrides() {
        let tab = TerminalTab(
            title: "SSH",
            profile: SessionProfile(name: "SSH", host: "host", protocolType: .ssh),
            remoteEnvironmentOverride: "TAB=1",
            remoteWorkingDirectoryOverride: "/tmp"
        )
        XCTAssertEqual(tab.remoteEnvironmentOverride, "TAB=1")
        XCTAssertEqual(tab.remoteWorkingDirectoryOverride, "/tmp")
    }
}
