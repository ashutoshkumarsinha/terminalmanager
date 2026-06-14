import Foundation
import XCTest
@testable import terminalmanager

/// Isolated config directory for tests via `TERMINALMANAGER_CONFIG`.
class TempConfigTestCase: XCTestCase {
    private(set) var tempConfigDirectory: URL!
    private var previousConfigEnv: String?

    override func setUp() {
        super.setUp()
        tempConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminalmanager-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempConfigDirectory, withIntermediateDirectories: true)
        previousConfigEnv = ProcessInfo.processInfo.environment["TERMINALMANAGER_CONFIG"]
        setenv("TERMINALMANAGER_CONFIG", tempConfigDirectory.path, 1)
    }

    override func tearDown() {
        if let previousConfigEnv {
            setenv("TERMINALMANAGER_CONFIG", previousConfigEnv, 1)
        } else {
            unsetenv("TERMINALMANAGER_CONFIG")
        }
        try? FileManager.default.removeItem(at: tempConfigDirectory)
        super.tearDown()
    }

    func makeSession(
        name: String,
        host: String,
        username: String = "admin",
        protocolType: ConnectionProtocol = .ssh
    ) -> SessionProfile {
        SessionProfile(name: name, host: host, username: username, protocolType: protocolType)
    }
}
