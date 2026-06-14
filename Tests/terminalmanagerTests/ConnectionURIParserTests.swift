import XCTest
@testable import terminalmanager

final class ConnectionURIParserTests: XCTestCase {
    func testParsesSSHURI() {
        let parsed = ConnectionURIParser.parse("ssh://admin@web01.example.com:2222")
        XCTAssertEqual(parsed?.protocolType, .ssh)
        XCTAssertEqual(parsed?.host, "web01.example.com")
        XCTAssertEqual(parsed?.port, 2222)
        XCTAssertEqual(parsed?.username, "admin")
    }

    func testParsesSSH2AsSSH() {
        let parsed = ConnectionURIParser.parse("ssh2://user@host")
        XCTAssertEqual(parsed?.protocolType, .ssh)
    }

    func testLooksLikeURI() {
        XCTAssertTrue(ConnectionURIParser.looksLikeURI("ssh://host"))
        XCTAssertFalse(ConnectionURIParser.looksLikeURI("plain-hostname"))
    }

    func testParsesTelnetAndRawSchemes() {
        XCTAssertEqual(ConnectionURIParser.parse("telnet://console:2323")?.protocolType, .telnet)
        XCTAssertEqual(ConnectionURIParser.parse("telnet://console:2323")?.port, 2323)
        XCTAssertEqual(ConnectionURIParser.parse("raw://device:9000")?.protocolType, .raw)
    }

    func testQuickConnectFromURI() {
        guard let profile = SessionProfile.quickConnect(from: "ssh://deploy@prod.example.com:2222") else {
            return XCTFail("Expected profile")
        }
        XCTAssertEqual(profile.host, "prod.example.com")
        XCTAssertEqual(profile.username, "deploy")
        XCTAssertEqual(profile.port, 2222)
        XCTAssertEqual(profile.protocolType, .ssh)
    }

    func testQuickConnectReturnsNilForInvalidInput() {
        XCTAssertNil(SessionProfile.quickConnect(from: ""))
        XCTAssertNil(SessionProfile.quickConnect(from: "not-a-uri"))
    }

    func testApplyParsedURIToProfile() {
        var profile = SessionProfile(name: "Temp", host: "", protocolType: .local)
        profile.apply(parsedURI: ParsedConnectionURI(
            protocolType: .telnet,
            host: "switch01",
            port: 2323,
            username: "admin"
        ))
        XCTAssertEqual(profile.host, "switch01")
        XCTAssertEqual(profile.port, 2323)
        XCTAssertEqual(profile.username, "admin")
        XCTAssertEqual(profile.protocolType, .telnet)
    }
}
