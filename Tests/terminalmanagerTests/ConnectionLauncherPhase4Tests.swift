import XCTest
@testable import terminalmanager

@MainActor
final class ConnectionLauncherPhase4Tests: XCTestCase {
    func testBastionProfileSetsProxyJumpWhenUnset() {
        let bastionID = UUID()
        let bastion = BastionProfile(id: bastionID, name: "Corp", host: "jump.example.com", username: "alice")
        var profile = SessionProfile(name: "Internal", host: "internal", username: "root", protocolType: .ssh)
        profile.bastionProfileID = bastionID

        let args = ConnectionLauncher.command(for: profile, bastions: [bastion]).arguments
        XCTAssertTrue(args.contains("-J"))
        XCTAssertTrue(args.contains("alice@jump.example.com"))
    }

    func testExplicitProxyJumpOverridesBastionProfile() {
        let bastionID = UUID()
        let bastion = BastionProfile(id: bastionID, name: "Corp", host: "jump.example.com")
        var profile = SessionProfile(name: "Internal", host: "internal", protocolType: .ssh, proxyJump: "manual.example.com")
        profile.bastionProfileID = bastionID

        let args = ConnectionLauncher.command(for: profile, bastions: [bastion]).arguments
        XCTAssertTrue(args.contains("manual.example.com"))
        XCTAssertFalse(args.contains("jump.example.com"))
    }

    func testRemoteEnvironmentAndWorkingDirectoryInStartup() {
        var profile = SessionProfile(name: "Web", host: "web01", username: "deploy", protocolType: .ssh)
        profile.remoteEnvironment = "APP_ENV=prod\nDEBUG=0"
        profile.remoteWorkingDirectory = "/srv/app"

        let startup = ConnectionLauncher.resolvedStartupCommands(for: profile)
        XCTAssertTrue(startup.commands.contains("export APP_ENV=prod"))
        XCTAssertTrue(startup.commands.contains("export DEBUG=0"))
        XCTAssertTrue(startup.commands.contains("cd '/srv/app'"))
    }

    func testTabOverridesAppliedViaCommandBuilder() {
        var profile = SessionProfile(name: "Web", host: "web01", protocolType: .ssh)
        profile.remoteEnvironment = "BASE=1"
        profile.remoteWorkingDirectory = "/base"

        _ = ConnectionLauncher.command(
            for: profile,
            tabOverrides: (remoteEnvironment: "TAB=1", remoteWorkingDirectory: "/tab")
        )

        var overridden = profile
        overridden.remoteEnvironment = "TAB=1"
        overridden.remoteWorkingDirectory = "/tab"
        let startup = ConnectionLauncher.resolvedStartupCommands(for: overridden)
        XCTAssertTrue(startup.commands.contains("export TAB=1"))
        XCTAssertTrue(startup.commands.contains("cd '/tab'"))
    }

    func testBastionJumpSpecWithAndWithoutUsername() {
        let withUser = BastionProfile(name: "A", host: "host", username: "u")
        XCTAssertEqual(withUser.jumpSpec, "u@host")

        let withoutUser = BastionProfile(name: "B", host: "host", username: "")
        XCTAssertEqual(withoutUser.jumpSpec, "host")
    }
}
