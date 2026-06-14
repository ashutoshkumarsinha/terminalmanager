import XCTest
@testable import terminalmanager

final class ConnectionTesterTests: XCTestCase {
    func testLocalProfileSucceedsImmediately() async {
        let profile = SessionProfile(name: "Local", host: "", protocolType: .local)
        let result = await ConnectionTester.testConnection(for: profile)
        XCTAssertEqual(result, .success)
    }

    func testEmptyHostFailsForSSH() async {
        let profile = SessionProfile(name: "Bad", host: "   ", protocolType: .ssh)
        let result = await ConnectionTester.testConnection(for: profile)
        guard case .failure(let message) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(message, "Host is empty")
    }

    func testEmptyHostFailsForRawTCP() async {
        let profile = SessionProfile(name: "Bad", host: "", port: 8080, protocolType: .raw)
        let result = await ConnectionTester.testConnection(for: profile)
        guard case .failure(let message) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(message, "Host is empty")
    }
}
