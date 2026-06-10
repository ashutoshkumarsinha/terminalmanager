import Foundation
import TOMLKit

enum TomlConfigCodec {
    private struct TomlRoot: Codable {
        var app: AppTable
        var window: WindowTable?
        var terminal: TerminalTable
        var ui: UITable
        var sessions: SessionsTable
        var logging: LoggingTable?
        var shortcuts: [ShortcutTable]

        struct AppTable: Codable {
            var version: Int
            var singleInstance: Bool?

            enum CodingKeys: String, CodingKey {
                case version
                case singleInstance = "single_instance"
            }
        }

        struct WindowTable: Codable {
            var startMaximized: Bool?
            var restorePosition: Bool?

            enum CodingKeys: String, CodingKey {
                case startMaximized = "start_maximized"
                case restorePosition = "restore_position"
            }
        }

        struct TerminalTable: Codable {
            var appPath: String
            var backend: String

            enum CodingKeys: String, CodingKey {
                case appPath = "app_path"
                case backend
            }
        }

        struct UITable: Codable {
            var showSidebar: Bool
            var showCommandBar: Bool?
            var broadcastEnabled: Bool
            var confirmOnExit: Bool?

            enum CodingKeys: String, CodingKey {
                case showSidebar = "show_sidebar"
                case showCommandBar = "show_command_bar"
                case broadcastEnabled = "broadcast_enabled"
                case confirmOnExit = "confirm_on_exit"
            }
        }

        struct SessionsTable: Codable {
            var file: String
        }

        struct LoggingTable: Codable {
            var level: String
        }

        struct ShortcutTable: Codable {
            var id: String
            var key: String
            var modifiers: [String]
        }
    }

    static func decode(from url: URL) throws -> AppSettings {
        let text = try String(contentsOf: url, encoding: .utf8)
        let table = try TOMLTable(string: text)
        let root = try TOMLDecoder().decode(TomlRoot.self, from: table)
        return appSettings(from: root)
    }

    static func encode(_ settings: AppSettings) throws -> String {
        let root = tomlRoot(from: settings)
        return try TOMLEncoder().encode(root)
    }

    static func write(_ settings: AppSettings, to url: URL) throws {
        let text = try encode(settings)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func appSettings(from root: TomlRoot) -> AppSettings {
        AppSettings(
            version: root.app.version,
            singleInstance: root.app.singleInstance ?? false,
            startMaximized: root.window?.startMaximized ?? false,
            restoreWindowPosition: root.window?.restorePosition ?? true,
            terminalAppPath: root.terminal.appPath,
            terminalBackend: TerminalBackend(rawValue: root.terminal.backend) ?? .embedded,
            sessionsFile: root.sessions.file,
            keyboardShortcuts: root.shortcuts.map {
                KeyboardShortcutBinding(id: $0.id, key: $0.key, modifiers: $0.modifiers)
            },
            showSidebar: root.ui.showSidebar,
            showCommandBar: root.ui.showCommandBar ?? true,
            broadcastEnabled: root.ui.broadcastEnabled,
            confirmOnExit: root.ui.confirmOnExit ?? false,
            logLevel: LogLevel(rawValue: root.logging?.level ?? "info") ?? .info
        )
    }

    private static func tomlRoot(from settings: AppSettings) -> TomlRoot {
        TomlRoot(
            app: .init(version: settings.version, singleInstance: settings.singleInstance),
            window: .init(
                startMaximized: settings.startMaximized,
                restorePosition: settings.restoreWindowPosition
            ),
            terminal: .init(appPath: settings.terminalAppPath, backend: settings.terminalBackend.rawValue),
            ui: .init(
                showSidebar: settings.showSidebar,
                showCommandBar: settings.showCommandBar,
                broadcastEnabled: settings.broadcastEnabled,
                confirmOnExit: settings.confirmOnExit
            ),
            sessions: .init(file: settings.sessionsFile),
            logging: .init(level: settings.logLevel.rawValue),
            shortcuts: settings.keyboardShortcuts.map {
                .init(id: $0.id, key: $0.key, modifiers: $0.modifiers)
            }
        )
    }
}
