import Foundation

enum ConnectionProtocol: String, Codable, CaseIterable, Identifiable {
    case ssh
    case telnet
    case rlogin
    case raw
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ssh: "SSH"
        case .telnet: "Telnet"
        case .rlogin: "Rlogin"
        case .raw: "Raw TCP"
        case .local: "Local Shell"
        }
    }

    var defaultPort: Int? {
        switch self {
        case .ssh: 22
        case .telnet: 23
        case .rlogin: 513
        case .raw: nil
        case .local: nil
        }
    }
}

enum SSHAuthMethod: String, Codable, CaseIterable, Identifiable {
    case agent
    case password
    case privateKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .agent: "SSH Agent (default)"
        case .password: "Password"
        case .privateKey: "Private Key"
        }
    }
}

enum TerminalBackend: String, Codable, CaseIterable, Identifiable {
    case embedded
    case ghostty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .embedded: "Embedded Terminal"
        case .ghostty: "Ghostty"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "ghostty", "terminalApp":
            self = .ghostty
        case "embedded":
            self = .embedded
        default:
            self = .embedded
        }
    }
}

struct SessionProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int?
    var username: String
    var protocolType: ConnectionProtocol
    var sshAuthMethod: SSHAuthMethod
    var password: String
    var sshKeyPath: String?
    var initScript: String
    var startupScriptPath: String?
    var sftpEnabled: Bool
    var notes: String
    var initialDirectory: String?

    init(
        id: UUID = UUID(),
        name: String,
        host: String = "",
        port: Int? = nil,
        username: String = "",
        protocolType: ConnectionProtocol = .ssh,
        sshAuthMethod: SSHAuthMethod = .agent,
        password: String = "",
        sshKeyPath: String? = nil,
        initScript: String = "",
        startupScriptPath: String? = nil,
        sftpEnabled: Bool = false,
        notes: String = "",
        initialDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port ?? protocolType.defaultPort
        self.username = username
        self.protocolType = protocolType
        self.sshAuthMethod = sshAuthMethod
        self.password = password
        self.sshKeyPath = sshKeyPath
        self.initScript = initScript
        self.startupScriptPath = startupScriptPath
        self.sftpEnabled = sftpEnabled
        self.notes = notes
        self.initialDirectory = initialDirectory
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, protocolType
        case sshAuthMethod, password, sshKeyPath
        case initScript, startupScriptPath
        case sftpEnabled, notes, initialDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        protocolType = try container.decode(ConnectionProtocol.self, forKey: .protocolType)
        sshAuthMethod = try container.decodeIfPresent(SSHAuthMethod.self, forKey: .sshAuthMethod) ?? .agent
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        sshKeyPath = try container.decodeIfPresent(String.self, forKey: .sshKeyPath)
        initScript = try container.decodeIfPresent(String.self, forKey: .initScript) ?? ""
        startupScriptPath = try container.decodeIfPresent(String.self, forKey: .startupScriptPath)
        sftpEnabled = try container.decodeIfPresent(Bool.self, forKey: .sftpEnabled) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        initialDirectory = try container.decodeIfPresent(String.self, forKey: .initialDirectory)
        if port == nil {
            port = protocolType.defaultPort
        }
    }
}

enum SessionTreeItem: Identifiable, Codable, Hashable {
    case folder(SessionFolder)
    case session(SessionProfile)
    case group(SessionGroup)

    var id: UUID {
        switch self {
        case .folder(let folder): folder.id
        case .session(let session): session.id
        case .group(let group): group.id
        }
    }

    var name: String {
        switch self {
        case .folder(let folder): folder.name
        case .session(let session): session.name
        case .group(let group): group.name
        }
    }
}

struct SessionGroupMember: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionID: UUID

    init(id: UUID = UUID(), sessionID: UUID) {
        self.id = id
        self.sessionID = sessionID
    }
}

struct SessionGroup: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var members: [SessionGroupMember]
    var layout: GroupLayoutNode?

    init(
        id: UUID = UUID(),
        name: String,
        members: [SessionGroupMember] = [],
        layout: GroupLayoutNode? = nil
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.layout = layout
    }
}

struct GroupLayoutNode: Identifiable, Codable, Hashable {
    let id: UUID
    var orientation: SplitOrientation?
    var memberID: UUID?
    var children: [GroupLayoutNode]
    var ratio: Double

    init(
        id: UUID = UUID(),
        orientation: SplitOrientation? = nil,
        memberID: UUID? = nil,
        children: [GroupLayoutNode] = [],
        ratio: Double = 0.5
    ) {
        self.id = id
        self.orientation = orientation
        self.memberID = memberID
        self.children = children
        self.ratio = ratio
    }

    static func leaf(memberID: UUID) -> GroupLayoutNode {
        GroupLayoutNode(memberID: memberID)
    }

    static func split(
        _ orientation: SplitOrientation,
        _ left: GroupLayoutNode,
        _ right: GroupLayoutNode,
        ratio: Double = 0.5
    ) -> GroupLayoutNode {
        GroupLayoutNode(orientation: orientation, children: [left, right], ratio: ratio)
    }

    var isLeaf: Bool { memberID != nil }
}

struct SessionFolder: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var children: [SessionTreeItem]

    init(id: UUID = UUID(), name: String, children: [SessionTreeItem] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

struct KeyboardShortcutBinding: Codable, Hashable, Identifiable {
    var id: String
    var key: String
    var modifiers: [String]

    init(id: String, key: String, modifiers: [String] = ["command"]) {
        self.id = id
        self.key = key
        self.modifiers = modifiers
    }
}

struct AppSettings: Equatable {
    var version: Int
    var singleInstance: Bool
    var startMaximized: Bool
    var restoreWindowPosition: Bool
    var terminalAppPath: String
    var terminalBackend: TerminalBackend
    var sessionsFile: String
    var keyboardShortcuts: [KeyboardShortcutBinding]
    var showSidebar: Bool
    var showCommandBar: Bool
    var broadcastEnabled: Bool
    var confirmOnExit: Bool
    var logLevel: LogLevel

    static let defaults = AppSettings(
        version: 1,
        singleInstance: false,
        startMaximized: false,
        restoreWindowPosition: true,
        terminalAppPath: GhosttyBridge.defaultAppPath,
        terminalBackend: .embedded,
        sessionsFile: "sessions.json",
        keyboardShortcuts: [
            KeyboardShortcutBinding(id: "newTab", key: "t"),
            KeyboardShortcutBinding(id: "closeTab", key: "w"),
            KeyboardShortcutBinding(id: "nextTab", key: "]", modifiers: ["command", "shift"]),
            KeyboardShortcutBinding(id: "prevTab", key: "[", modifiers: ["command", "shift"]),
            KeyboardShortcutBinding(id: "duplicateSession", key: "d"),
            KeyboardShortcutBinding(id: "commandBar", key: "l", modifiers: ["command", "shift"])
        ],
        showSidebar: true,
        showCommandBar: true,
        broadcastEnabled: true,
        confirmOnExit: false,
        logLevel: .info
    )
}

struct SessionConfiguration: Codable {
    var version: Int
    var sessionTree: [SessionTreeItem]

    static let empty = SessionConfiguration(version: 1, sessionTree: [])
}

enum SplitOrientation: String, Codable {
    case horizontal
    case vertical
}

struct TerminalTab: Identifiable, Hashable {
    let id: UUID
    var title: String
    var profile: SessionProfile?
    var backend: TerminalBackend
    var isDetached: Bool
    /// Split panes share a tab-strip entry with their anchor tab and are not shown as separate tabs.
    var isSplitPane: Bool
    var initScript: String

    init(
        id: UUID = UUID(),
        title: String,
        profile: SessionProfile? = nil,
        backend: TerminalBackend = .embedded,
        isDetached: Bool = false,
        isSplitPane: Bool = false,
        initScript: String = ""
    ) {
        self.id = id
        self.title = title
        self.profile = profile
        self.backend = backend
        self.isDetached = isDetached
        self.isSplitPane = isSplitPane
        self.initScript = initScript
    }
}

struct SplitLayoutNode: Identifiable, Hashable {
    let id: UUID
    var orientation: SplitOrientation?
    var tabID: UUID?
    var children: [SplitLayoutNode]
    var ratio: Double

    init(
        id: UUID = UUID(),
        orientation: SplitOrientation? = nil,
        tabID: UUID? = nil,
        children: [SplitLayoutNode] = [],
        ratio: Double = 0.5
    ) {
        self.id = id
        self.orientation = orientation
        self.tabID = tabID
        self.children = children
        self.ratio = ratio
    }

    static func leaf(tabID: UUID) -> SplitLayoutNode {
        SplitLayoutNode(tabID: tabID)
    }

    static func split(_ orientation: SplitOrientation, _ left: SplitLayoutNode, _ right: SplitLayoutNode, ratio: Double = 0.5) -> SplitLayoutNode {
        SplitLayoutNode(orientation: orientation, children: [left, right], ratio: ratio)
    }

    var isLeaf: Bool { tabID != nil }

    var isSplitTree: Bool { tabID == nil && children.count == 2 }

    func tabIDsInLayout() -> Set<UUID> {
        if let tabID { return [tabID] }
        return Set(children.flatMap { $0.tabIDsInLayout() })
    }
}
