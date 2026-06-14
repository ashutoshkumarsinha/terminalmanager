import XCTest
@testable import terminalmanager

final class UpdateCheckerTests: XCTestCase {
    private var session: URLSession!
    private var previousSession: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        previousSession = UpdateCheckerTesting.urlSession
        UpdateCheckerTesting.urlSession = session
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        UpdateCheckerTesting.urlSession = previousSession
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testReturnsURLWhenNewerVersionAvailable() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {"tag_name":"v2.0.0","html_url":"https://github.com/org/repo/releases/tag/v2.0.0","body":"Bug fixes"}
            """.data(using: .utf8)!
            return (response, body)
        }

        let url = await UpdateChecker.checkForUpdate(currentVersion: "1.0.0", repository: "org/repo")
        XCTAssertEqual(url, "https://github.com/org/repo/releases/tag/v2.0.0")

        let info = await UpdateChecker.fetchUpdateInfo(currentVersion: "1.0.0", repository: "org/repo")
        XCTAssertEqual(info?.version, "v2.0.0")
        XCTAssertEqual(info?.releaseNotes, "Bug fixes")
    }

    func testReturnsNilWhenAlreadyUpToDate() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"tag_name":"v1.0.0","html_url":"https://github.com/org/repo/releases/tag/v1.0.0"}
            """.data(using: .utf8)!
            return (response, body)
        }

        let url = await UpdateChecker.checkForUpdate(currentVersion: "1.0.0", repository: "org/repo")
        XCTAssertNil(url)
    }

    func testReturnsNilOnHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let url = await UpdateChecker.checkForUpdate(currentVersion: "1.0.0", repository: "org/repo")
        XCTAssertNil(url)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
