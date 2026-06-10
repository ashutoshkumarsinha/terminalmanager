import Foundation

enum FileLocations {
    private static let configDirName = ".terminalmanager"
    private static let legacyConfigDirName = "terminalmanager"

    /// Config root directory. `TERMINALMANAGER_CONFIG` may point to a directory or a `config.toml` file.
    static var configDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["TERMINALMANAGER_CONFIG"] {
            let url = URL(fileURLWithPath: override)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return url
                }
                if url.pathExtension.lowercased() == "toml" {
                    return url.deletingLastPathComponent()
                }
            }
            return url.deletingLastPathComponent()
        }

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(configDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        migrateLegacyConfigIfNeeded(to: dir)
        return dir
    }

    /// One-time migration from `~/Library/Application Support/terminalmanager`.
    private static func migrateLegacyConfigIfNeeded(to newDir: URL) {
        let fm = FileManager.default
        let newConfig = newDir.appendingPathComponent("config.toml")
        guard !fm.fileExists(atPath: newConfig.path) else { return }

        let legacyDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(legacyConfigDirName, isDirectory: true)
        guard fm.fileExists(atPath: legacyDir.path) else { return }

        for name in ["config.toml", "sessions.json"] {
            let source = legacyDir.appendingPathComponent(name)
            let destination = newDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.path) else { continue }
            try? fm.copyItem(at: source, to: destination)
        }

        if let legacyFiles = try? fm.contentsOfDirectory(atPath: legacyDir.path) {
            for file in legacyFiles where file.hasPrefix("askpass-") && file.hasSuffix(".sh") {
                let source = legacyDir.appendingPathComponent(file)
                let destination = newDir.appendingPathComponent(file)
                guard !fm.fileExists(atPath: destination.path) else { continue }
                try? fm.copyItem(at: source, to: destination)
            }
        }
    }

    static var configTomlURL: URL {
        if let override = ProcessInfo.processInfo.environment["TERMINALMANAGER_CONFIG"] {
            let url = URL(fileURLWithPath: override)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               url.pathExtension.lowercased() == "toml" {
                return url
            }
        }
        return configDirectory.appendingPathComponent("config.toml")
    }

    static func sessionsURL(for sessionsFile: String) -> URL {
        if sessionsFile.hasPrefix("/") {
            return URL(fileURLWithPath: sessionsFile)
        }
        return configDirectory.appendingPathComponent(sessionsFile)
    }

    static var logsDirectory: URL {
        configDirectory.appendingPathComponent("logs", isDirectory: true)
    }
}
