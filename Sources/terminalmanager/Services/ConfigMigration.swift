import Foundation

/// Applies config schema migrations when loading `config.toml` (TE-05).
enum ConfigMigration {
    static let currentSchemaVersion = 2

    static func migrate(_ settings: inout AppSettings) {
        let from = settings.configSchemaVersion
        guard from < currentSchemaVersion else { return }

        if from < 2 {
            // v2: performance keys defaulted in AppSettings; no transform needed.
        }

        settings.configSchemaVersion = currentSchemaVersion
        AppLogger.shared.info("Migrated config schema v\(from) → v\(currentSchemaVersion)")
    }
}
