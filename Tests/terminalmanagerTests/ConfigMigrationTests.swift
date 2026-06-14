import XCTest
@testable import terminalmanager

final class ConfigMigrationTests: XCTestCase {
    func testMigrateFromSchema1ToCurrent() {
        var settings = AppSettings.defaults
        settings.configSchemaVersion = 1
        ConfigMigration.migrate(&settings)
        XCTAssertEqual(settings.configSchemaVersion, ConfigMigration.currentSchemaVersion)
    }

    func testMigrateIsIdempotent() {
        var settings = AppSettings.defaults
        ConfigMigration.migrate(&settings)
        let version = settings.configSchemaVersion
        ConfigMigration.migrate(&settings)
        XCTAssertEqual(settings.configSchemaVersion, version)
    }
}
