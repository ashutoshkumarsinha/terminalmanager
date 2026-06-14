import XCTest
@testable import terminalmanager

final class AppDelegateTests: XCTestCase {
    func testParsesTerminalManagerURLScheme() {
        let url = URL(string: "terminalmanager://open?uri=ssh%3A%2F%2Fadmin%40web01.example.com%3A22")!
        XCTAssertEqual(
            AppDelegate.connectionString(from: url),
            "ssh://admin@web01.example.com:22"
        )
    }

    func testIgnoresTerminalManagerURLWithoutURIParameter() {
        let url = URL(string: "terminalmanager://open")!
        XCTAssertNil(AppDelegate.connectionString(from: url))
    }

    func testPassesThroughNonCustomSchemes() {
        let url = URL(string: "ssh://user@host:22")!
        XCTAssertEqual(AppDelegate.connectionString(from: url), "ssh://user@host:22")
    }
}
