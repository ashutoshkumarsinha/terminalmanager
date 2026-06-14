import XCTest
@testable import terminalmanager

final class SessionTemplateStoreTests: TempConfigTestCase {
    func testAddUpdateDeleteTemplates() throws {
        var settings = AppSettings.defaults
        let template = SessionTemplate(
            name: "Prod SSH",
            protocolType: .ssh,
            username: "deploy",
            port: 22,
            proxyJump: "jump.host",
            tagColor: "#FF0000"
        )

        let added = try SessionTemplateStore.add(template, to: &settings)
        XCTAssertEqual(added.name, "Prod SSH")
        XCTAssertEqual(settings.sessionTemplates.count, 1)

        var updated = added
        updated.username = "root"
        let saved = try SessionTemplateStore.update(updated, in: &settings)
        XCTAssertEqual(saved.username, "root")

        try SessionTemplateStore.delete(id: saved.id, from: &settings)
        XCTAssertTrue(settings.sessionTemplates.isEmpty)
        XCTAssertTrue(SessionTemplateStore.load().isEmpty)
    }

    func testAddDuplicateNameGetsUniqueSuffix() throws {
        var settings = AppSettings.defaults
        _ = try SessionTemplateStore.add(
            SessionTemplate(name: "Web", protocolType: .ssh),
            to: &settings
        )
        let second = try SessionTemplateStore.add(
            SessionTemplate(name: "Web", protocolType: .ssh),
            to: &settings
        )
        XCTAssertEqual(second.name, "Web 2")
    }

    func testAllTemplatesMergesFileAndSettings() throws {
        var settings = AppSettings.defaults
        let fromSettings = SessionTemplate(id: UUID(), name: "From Settings", protocolType: .ssh)
        settings.sessionTemplates = [fromSettings]

        let fromFile = SessionTemplate(id: UUID(), name: "From File", protocolType: .telnet)
        try SessionTemplateStore.save([fromFile])

        let merged = SessionTemplateStore.allTemplates(from: settings)
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(where: { $0.name == "From Settings" }))
        XCTAssertTrue(merged.contains(where: { $0.name == "From File" }))
    }
}
