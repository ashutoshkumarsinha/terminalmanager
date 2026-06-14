import XCTest
@testable import terminalmanager

@MainActor
final class ConnectionLauncherTests: XCTestCase {
    func testSSHIncludesProxyJump() {
        var profile = SessionProfile(name: "Bastion", host: "internal", username: "root", protocolType: .ssh)
        profile.proxyJump = "jump.example.com"
        let args = sshArguments(from: profile)
        XCTAssertTrue(args.contains("-J"))
        XCTAssertTrue(args.contains("jump.example.com"))
    }

    func testSSHIncludesExtraOptions() {
        var profile = SessionProfile(name: "Custom", host: "host", username: "user", protocolType: .ssh)
        profile.sshExtraOptions = """
        -o IdentityFile=~/.ssh/work
        -o UserKnownHostsFile=/dev/null
        """
        let args = sshArguments(from: profile)
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains { $0.contains("IdentityFile=~/.ssh/work") })
        XCTAssertTrue(args.contains { $0.contains("UserKnownHostsFile=/dev/null") })
    }

    func testSFTPIncludesProxyJumpAndPort() {
        var profile = SessionProfile(name: "SFTP", host: "files", port: 2222, username: "user", protocolType: .ssh)
        profile.proxyJump = "bastion"
        guard let command = ConnectionLauncher.sftpCommand(for: profile) else {
            return XCTFail("Expected SFTP command")
        }
        XCTAssertEqual(command.executable, "/usr/bin/sftp")
        XCTAssertTrue(command.arguments.contains("-P"))
        XCTAssertTrue(command.arguments.contains("2222"))
        XCTAssertTrue(command.arguments.contains("-J"))
        XCTAssertTrue(command.arguments.contains("bastion"))
    }

    func testInitScriptLinesSkipsCommentsAndBlankLines() {
        let lines = ConnectionLauncher.initScriptLines(from: """
        cd /var/log

        # comment
        tail -f app.log
        """)
        XCTAssertEqual(lines, ["cd /var/log", "tail -f app.log"])
    }

    func testTelnetCommandUsesDefaultPort() {
        let profile = SessionProfile(name: "Telnet", host: "console", protocolType: .telnet)
        let command = ConnectionLauncher.command(for: profile)
        XCTAssertEqual(command.executable, "/usr/bin/telnet")
        XCTAssertEqual(command.arguments, ["console", "23"])
    }

    func testRawTCPUsesNetcat() {
        let profile = SessionProfile(name: "Raw", host: "device", port: 9000, protocolType: .raw)
        let command = ConnectionLauncher.command(for: profile)
        XCTAssertEqual(command.executable, "/usr/bin/nc")
        XCTAssertEqual(command.arguments, ["device", "9000"])
    }

    func testAppendSSHExtraOptionsParsesDashOAndFlags() {
        var args: [String] = []
        ConnectionLauncher.appendSSHExtraOptions(
            """
            -o ForwardAgent=yes
            -L 8080:localhost:80
            # ignored
            """,
            to: &args
        )
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("ForwardAgent=yes"))
        XCTAssertEqual(args.filter { $0 == "-L" }.count, 1)
        XCTAssertTrue(args.contains("8080:localhost:80"))
    }

    func testNormalizedPayloadSplitsLines() {
        let payload = BroadcastManager.normalizedPayload(from: "line1\nline2")
        XCTAssertEqual(payload, "line1\nline2\n")
    }

    private func sshArguments(from profile: SessionProfile) -> [String] {
        ConnectionLauncher.command(for: profile).arguments
    }
}
