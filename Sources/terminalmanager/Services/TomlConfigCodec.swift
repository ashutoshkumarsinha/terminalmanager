import Foundation
import TOMLKit

enum TomlConfigCodec {
    private struct TomlRoot: Codable {
        var app: AppTable
        var window: WindowTable?
        var terminal: TerminalTable?
        var ui: UITable
        var sessions: SessionsTable
        var logging: LoggingTable?
        var performance: PerformanceTable?
        var shortcuts: [ShortcutTable]
        var templates: [TemplateTable]?

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
            var appPath: String?
            var backend: String?
            var fontName: String?
            var fontSize: Double?
            var theme: String?
            var restoreTabsOnLaunch: Bool?
            var autoReconnect: Bool?

            enum CodingKeys: String, CodingKey {
                case appPath = "app_path"
                case backend
                case fontName = "font_name"
                case fontSize = "font_size"
                case theme
                case restoreTabsOnLaunch = "restore_tabs_on_launch"
                case autoReconnect = "auto_reconnect"
            }
        }

        struct UITable: Codable {
            var showSidebar: Bool
            var showCommandBar: Bool?
            var showTooltips: Bool?
            var broadcastEnabled: Bool
            var confirmOnExit: Bool?

            enum CodingKeys: String, CodingKey {
                case showSidebar = "show_sidebar"
                case showCommandBar = "show_command_bar"
                case showTooltips = "show_tooltips"
                case broadcastEnabled = "broadcast_enabled"
                case confirmOnExit = "confirm_on_exit"
            }
        }

        struct SessionsTable: Codable {
            var file: String
            var syncPath: String?

            enum CodingKeys: String, CodingKey {
                case file
                case syncPath = "sync_path"
            }
        }

        struct LoggingTable: Codable {
            var level: String
            var logTerminalIO: Bool?
            var terminalIOMaxMB: Int?

            enum CodingKeys: String, CodingKey {
                case level
                case logTerminalIO = "log_terminal_io"
                case terminalIOMaxMB = "terminal_io_max_mb"
            }
        }

        struct PerformanceTable: Codable {
            var launchStateDebounceMs: Int?
            var sidebarSearchDebounceMs: Int?
            var maxScrollbackLines: Int?
            var sessionsSaveOffMain: Bool?
            var hibernateInactiveTabsMinutes: Int?
            var terminalIOMetadataOnly: Bool?

            enum CodingKeys: String, CodingKey {
                case launchStateDebounceMs = "launch_state_debounce_ms"
                case sidebarSearchDebounceMs = "sidebar_search_debounce_ms"
                case maxScrollbackLines = "max_scrollback_lines"
                case sessionsSaveOffMain = "sessions_save_off_main"
                case hibernateInactiveTabsMinutes = "hibernate_inactive_tabs_minutes"
                case terminalIOMetadataOnly = "terminal_io_metadata_only"
            }
        }

        struct TemplateTable: Codable {
            var id: UUID
            var name: String
            var protocolType: String
            var username: String?
            var port: Int?
            var sshAuthMethod: String?
            var sshKeyPath: String?
            var initScript: String?
            var proxyJump: String?
            var sshExtraOptions: String?
            var tagColor: String?

            enum CodingKeys: String, CodingKey {
                case id, name, username, port
                case protocolType = "protocol"
                case sshAuthMethod = "ssh_auth_method"
                case sshKeyPath = "ssh_key_path"
                case initScript = "init_script"
                case proxyJump = "proxy_jump"
                case sshExtraOptions = "ssh_extra_options"
                case tagColor = "tag_color"
            }
        }

        struct ShortcutTable: Codable {
            var id: String
            var key: String
            var modifiers: [String]
        }
    }

    static func decode(from url: URL) throws -> AppSettings {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try decode(fromString: text)
    }

    static func decode(fromString text: String) throws -> AppSettings {
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
        let defaults = AppSettings.defaults
        let terminal = root.terminal
        let logging = root.logging
        let performance = root.performance
        let templates = (root.templates ?? []).compactMap { sessionTemplate(from: $0) }

        return AppSettings(
            version: root.app.version,
            singleInstance: root.app.singleInstance ?? false,
            startMaximized: root.window?.startMaximized ?? false,
            restoreWindowPosition: root.window?.restorePosition ?? true,
            sessionsFile: root.sessions.file,
            keyboardShortcuts: root.shortcuts.map {
                KeyboardShortcutBinding(id: $0.id, key: $0.key, modifiers: $0.modifiers)
            },
            showSidebar: root.ui.showSidebar,
            showCommandBar: root.ui.showCommandBar ?? true,
            showTooltips: root.ui.showTooltips ?? true,
            broadcastEnabled: root.ui.broadcastEnabled,
            confirmOnExit: root.ui.confirmOnExit ?? false,
            logLevel: LogLevel(rawValue: logging?.level ?? "info") ?? .info,
            terminalFontName: terminal?.fontName ?? defaults.terminalFontName,
            terminalFontSize: terminal?.fontSize ?? defaults.terminalFontSize,
            terminalTheme: TerminalTheme(rawValue: terminal?.theme ?? "system") ?? .system,
            restoreTabsOnLaunch: terminal?.restoreTabsOnLaunch ?? defaults.restoreTabsOnLaunch,
            logTerminalIO: logging?.logTerminalIO ?? defaults.logTerminalIO,
            terminalIOMaxMB: logging?.terminalIOMaxMB ?? defaults.terminalIOMaxMB,
            autoReconnect: terminal?.autoReconnect ?? defaults.autoReconnect,
            syncSessionsPath: root.sessions.syncPath,
            sessionTemplates: templates.isEmpty ? SessionTemplateStore.load() : templates,
            launchStateDebounceMs: performance?.launchStateDebounceMs ?? defaults.launchStateDebounceMs,
            sidebarSearchDebounceMs: performance?.sidebarSearchDebounceMs ?? defaults.sidebarSearchDebounceMs,
            maxScrollbackLines: performance?.maxScrollbackLines ?? defaults.maxScrollbackLines,
            sessionsSaveOffMain: performance?.sessionsSaveOffMain ?? defaults.sessionsSaveOffMain,
            hibernateInactiveTabsMinutes: performance?.hibernateInactiveTabsMinutes ?? defaults.hibernateInactiveTabsMinutes,
            terminalIOMetadataOnly: performance?.terminalIOMetadataOnly ?? defaults.terminalIOMetadataOnly
        )
    }

    private static func sessionTemplate(from table: TomlRoot.TemplateTable) -> SessionTemplate? {
        guard let protocolType = ConnectionProtocol(rawValue: table.protocolType.lowercased()) else {
            return nil
        }
        return SessionTemplate(
            id: table.id,
            name: table.name,
            protocolType: protocolType,
            username: table.username ?? "",
            port: table.port ?? protocolType.defaultPort,
            sshAuthMethod: SSHAuthMethod(rawValue: table.sshAuthMethod ?? "agent") ?? .agent,
            sshKeyPath: table.sshKeyPath,
            initScript: table.initScript ?? "",
            proxyJump: table.proxyJump,
            sshExtraOptions: table.sshExtraOptions,
            tagColor: table.tagColor
        )
    }

    private static func tomlRoot(from settings: AppSettings) -> TomlRoot {
        TomlRoot(
            app: .init(version: settings.version, singleInstance: settings.singleInstance),
            window: .init(
                startMaximized: settings.startMaximized,
                restorePosition: settings.restoreWindowPosition
            ),
            terminal: .init(
                appPath: nil,
                backend: nil,
                fontName: settings.terminalFontName == AppSettings.defaults.terminalFontName ? nil : settings.terminalFontName,
                fontSize: settings.terminalFontSize == AppSettings.defaults.terminalFontSize ? nil : settings.terminalFontSize,
                theme: settings.terminalTheme == .system ? nil : settings.terminalTheme.rawValue,
                restoreTabsOnLaunch: settings.restoreTabsOnLaunch ? true : nil,
                autoReconnect: settings.autoReconnect == AppSettings.defaults.autoReconnect ? nil : settings.autoReconnect
            ),
            ui: .init(
                showSidebar: settings.showSidebar,
                showCommandBar: settings.showCommandBar,
                showTooltips: settings.showTooltips,
                broadcastEnabled: settings.broadcastEnabled,
                confirmOnExit: settings.confirmOnExit
            ),
            sessions: .init(
                file: settings.sessionsFile,
                syncPath: settings.syncSessionsPath
            ),
            logging: .init(
                level: settings.logLevel.rawValue,
                logTerminalIO: settings.logTerminalIO == AppSettings.defaults.logTerminalIO ? nil : settings.logTerminalIO,
                terminalIOMaxMB: settings.terminalIOMaxMB == AppSettings.defaults.terminalIOMaxMB ? nil : settings.terminalIOMaxMB
            ),
            performance: performanceTable(from: settings),
            shortcuts: settings.keyboardShortcuts.map {
                .init(id: $0.id, key: $0.key, modifiers: $0.modifiers)
            },
            templates: settings.sessionTemplates.isEmpty ? nil : settings.sessionTemplates.map { templateTable(from: $0) }
        )
    }

    private static func performanceTable(from settings: AppSettings) -> TomlRoot.PerformanceTable? {
        let defaults = AppSettings.defaults
        let table = TomlRoot.PerformanceTable(
            launchStateDebounceMs: settings.launchStateDebounceMs == defaults.launchStateDebounceMs
                ? nil : settings.launchStateDebounceMs,
            sidebarSearchDebounceMs: settings.sidebarSearchDebounceMs == defaults.sidebarSearchDebounceMs
                ? nil : settings.sidebarSearchDebounceMs,
            maxScrollbackLines: settings.maxScrollbackLines == defaults.maxScrollbackLines
                ? nil : settings.maxScrollbackLines,
            sessionsSaveOffMain: settings.sessionsSaveOffMain == defaults.sessionsSaveOffMain
                ? nil : settings.sessionsSaveOffMain,
            hibernateInactiveTabsMinutes: settings.hibernateInactiveTabsMinutes == defaults.hibernateInactiveTabsMinutes
                ? nil : settings.hibernateInactiveTabsMinutes,
            terminalIOMetadataOnly: settings.terminalIOMetadataOnly == defaults.terminalIOMetadataOnly
                ? nil : settings.terminalIOMetadataOnly
        )
        if table.launchStateDebounceMs == nil,
           table.sidebarSearchDebounceMs == nil,
           table.maxScrollbackLines == nil,
           table.sessionsSaveOffMain == nil,
           table.hibernateInactiveTabsMinutes == nil,
           table.terminalIOMetadataOnly == nil {
            return nil
        }
        return table
    }

    private static func templateTable(from template: SessionTemplate) -> TomlRoot.TemplateTable {
        TomlRoot.TemplateTable(
            id: template.id,
            name: template.name,
            protocolType: template.protocolType.rawValue,
            username: template.username.isEmpty ? nil : template.username,
            port: template.port,
            sshAuthMethod: template.sshAuthMethod.rawValue,
            sshKeyPath: template.sshKeyPath,
            initScript: template.initScript.isEmpty ? nil : template.initScript,
            proxyJump: template.proxyJump,
            sshExtraOptions: template.sshExtraOptions,
            tagColor: template.tagColor
        )
    }
}
