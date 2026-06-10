import Foundation

@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var settings: AppSettings = .defaults
    @Published private(set) var sessionTree: [SessionTreeItem] = []

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let jsonDecoder = JSONDecoder()

    var configTomlURL: URL { FileLocations.configTomlURL }

    var sessionsURL: URL {
        FileLocations.sessionsURL(for: settings.sessionsFile)
    }

    func load() {
        loadSettings()
        loadSessions()
    }

    func saveSettings() {
        do {
            try TomlConfigCodec.write(settings, to: configTomlURL)
        } catch {
            AppLogger.shared.error("Failed to save config.toml: \(error)")
        }
    }

    func saveSessions() {
        do {
            let config = SessionConfiguration(version: 1, sessionTree: sessionTree)
            let data = try jsonEncoder.encode(config)
            let url = sessionsURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.error("Failed to save sessions: \(error)")
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        let sessionsPathChanged = newSettings.sessionsFile != settings.sessionsFile
        settings = newSettings
        saveSettings()
        if sessionsPathChanged {
            loadSessions()
        }
    }

    func updateSessionTree(_ tree: [SessionTreeItem]) {
        sessionTree = tree
        saveSessions()
    }

    func exportSessions(to url: URL) throws {
        let config = SessionConfiguration(version: 1, sessionTree: sessionTree)
        let data = try jsonEncoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    func importSessions(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let config = try jsonDecoder.decode(SessionConfiguration.self, from: data)
        sessionTree = config.sessionTree
        saveSessions()
    }

    @discardableResult
    func addSession(_ profile: SessionProfile, to folderID: UUID? = nil) -> SessionProfile {
        let siblings = siblingItems(inFolderID: folderID)
        var saved = profile
        saved.name = uniqueSessionName(basedOn: profile.name, among: siblings)
        if let folderID {
            sessionTree = insertSession(saved, folderID: folderID, beforeItemID: nil, in: sessionTree)
        } else {
            sessionTree = insertItemInList(.session(saved), beforeItemID: nil, in: sessionTree)
        }
        saveSessions()
        return saved
    }

    @discardableResult
    func duplicateSession(id: UUID) -> SessionProfile? {
        guard let item = item(withID: id), case .session(let source) = item else { return nil }

        let parentFolderID = Self.parentFolderID(of: id, in: sessionTree)
        let siblings = siblingItems(inFolderID: parentFolderID)
        var copy = source
        copy.id = UUID()
        copy.name = uniqueSessionName(basedOn: source.name, among: siblings)

        let beforeItemID = siblingIDAfter(sessionID: id, in: siblings)
        if let parentFolderID {
            sessionTree = insertSession(copy, folderID: parentFolderID, beforeItemID: beforeItemID, in: sessionTree)
        } else {
            sessionTree = insertItemInList(.session(copy), beforeItemID: beforeItemID, in: sessionTree)
        }
        saveSessions()
        AppLogger.shared.info("Duplicated session '\(source.name)' as '\(copy.name)'")
        return copy
    }

    @discardableResult
    func addFolder(_ name: String) -> SessionFolder {
        let folder = SessionFolder(name: uniqueFolderName(basedOn: name))
        sessionTree = sessionTree + [.folder(folder)]
        saveSessions()
        return folder
    }

    @discardableResult
    func addGroup(_ name: String) -> SessionGroup {
        let group = SessionGroup(name: uniqueGroupName(basedOn: name))
        sessionTree = sessionTree + [.group(group)]
        saveSessions()
        return group
    }

    @discardableResult
    func saveGroup(name: String, members: [SessionGroupMember], layout: GroupLayoutNode?) -> SessionGroup {
        let group = SessionGroup(name: uniqueGroupName(basedOn: name), members: members, layout: layout)
        sessionTree = sessionTree + [.group(group)]
        saveSessions()
        return group
    }

    func group(withID id: UUID) -> SessionGroup? {
        guard let item = item(withID: id), case .group(let group) = item else { return nil }
        return group
    }

    func groupNameExists(_ name: String, excludingID: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Self.groupNames(in: sessionTree, excludingID: excludingID)
            .contains { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }

    @discardableResult
    func renameGroup(id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groupNameExists(trimmed, excludingID: id) else { return false }
        sessionTree = updateInTree(sessionTree, id: id) { item in
            guard case .group(var group) = item else { return item }
            group.name = trimmed
            return .group(group)
        }
        saveSessions()
        return true
    }

    @discardableResult
    func duplicateGroup(id: UUID) -> SessionGroup? {
        guard let item = item(withID: id), case .group(let source) = item else { return nil }

        var memberIDMap: [UUID: UUID] = [:]
        let members = source.members.map { member -> SessionGroupMember in
            let copy = SessionGroupMember(sessionID: member.sessionID)
            memberIDMap[member.id] = copy.id
            return copy
        }

        let layout = source.layout.flatMap { GroupLayoutMapper.remapMemberIDs(in: $0, map: memberIDMap) }
        let copy = SessionGroup(
            name: uniqueGroupName(basedOn: source.name),
            members: members,
            layout: layout
        )

        let beforeItemID = siblingIDAfter(sessionID: id, in: sessionTree)
        sessionTree = insertItemInList(.group(copy), beforeItemID: beforeItemID, in: sessionTree)
        saveSessions()
        AppLogger.shared.info("Duplicated group '\(source.name)' as '\(copy.name)'")
        return copy
    }

    @discardableResult
    func updateGroup(_ group: SessionGroup) -> Bool {
        guard self.group(withID: group.id) != nil else { return false }
        sessionTree = updateInTree(sessionTree, id: group.id) { item in
            guard case .group = item else { return item }
            return .group(group)
        }
        saveSessions()
        return true
    }

    @discardableResult
    func addSessionToGroup(groupID: UUID, sessionID: UUID) -> Bool {
        guard Self.findSessionProfile(id: sessionID, in: sessionTree) != nil,
              var group = group(withID: groupID) else {
            return false
        }
        group.members.append(SessionGroupMember(sessionID: sessionID))
        return updateGroup(group)
    }

    @discardableResult
    func removeMemberFromGroup(groupID: UUID, memberID: UUID) -> Bool {
        guard var group = group(withID: groupID) else { return false }
        let previousCount = group.members.count
        group.members.removeAll { $0.id == memberID }
        guard group.members.count != previousCount else { return false }
        if let layout = group.layout {
            group.layout = removeMemberFromGroupLayout(memberID, in: layout)
        }
        return updateGroup(group)
    }

    func folderNameExists(_ name: String, excludingID: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Self.folderNames(in: sessionTree, excludingID: excludingID)
            .contains { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }

    func sessionNameExists(_ name: String, excludingSessionID: UUID) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let siblings = siblingContainer(forSessionID: excludingSessionID) else { return false }
        return Self.sessionNames(in: siblings, excludingID: excludingSessionID)
            .contains { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }

    @discardableResult
    func updateSession(_ profile: SessionProfile) -> Bool {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sessionNameExists(trimmed, excludingSessionID: profile.id) else { return false }
        var saved = profile
        saved.name = trimmed
        sessionTree = updateInTree(sessionTree, id: profile.id) { item in
            guard case .session = item else { return item }
            return .session(saved)
        }
        saveSessions()
        return true
    }

    @discardableResult
    func renameFolder(id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !folderNameExists(trimmed, excludingID: id) else { return false }
        sessionTree = updateInTree(sessionTree, id: id) { item in
            guard case .folder(var folder) = item else { return item }
            folder.name = trimmed
            return .folder(folder)
        }
        saveSessions()
        return true
    }

    @discardableResult
    func removeItem(id: UUID) -> [SessionProfile] {
        guard let item = item(withID: id) else { return [] }
        let removedSessions = Self.collectSessions(in: item)
        sessionTree = removeFromTree(sessionTree, id: id)
        saveSessions()
        return removedSessions
    }

    /// `parentFolderID` is `nil` for the root list. `beforeItemID` inserts before that sibling; append when `nil`.
    @discardableResult
    func moveItem(withID itemID: UUID, toParentFolderID parentFolderID: UUID?, beforeItemID: UUID?) -> Bool {
        guard itemID != beforeItemID else { return false }
        if itemID == parentFolderID { return false }

        if let item = item(withID: itemID), case .folder(let sourceFolder) = item {
            if let parentFolderID, Self.isItem(parentFolderID, insideFolder: sourceFolder.id, in: sessionTree) {
                return false
            }
            if let beforeItemID, Self.isItem(beforeItemID, insideFolder: sourceFolder.id, in: sessionTree) {
                return false
            }
        }

        let extracted = extractItem(withID: itemID, from: sessionTree)
        guard var movingItem = extracted.item else { return false }

        if let parentFolderID, Self.findItem(id: parentFolderID, in: extracted.tree) == nil {
            return false
        }
        if let beforeItemID {
            let container = parentFolderID.flatMap { folderID in
                Self.findItem(id: folderID, in: extracted.tree).flatMap { item -> [SessionTreeItem]? in
                    guard case .folder(let folder) = item else { return nil }
                    return folder.children
                }
            } ?? extracted.tree
            guard container.contains(where: { $0.id == beforeItemID }) else { return false }
        }

        movingItem = resolveNamingConflicts(movingItem, parentFolderID: parentFolderID)
        sessionTree = insertItem(
            movingItem,
            parentFolderID: parentFolderID,
            beforeItemID: beforeItemID,
            in: extracted.tree
        )
        saveSessions()
        AppLogger.shared.info("Moved session item \(itemID)")
        return true
    }

    static func parentFolderID(of itemID: UUID, in items: [SessionTreeItem]) -> UUID? {
        let result = parentFolderID(of: itemID, in: items, parentID: nil)
        return result.found ? result.parentID : nil
    }

    static func isItem(_ itemID: UUID, insideFolder folderID: UUID, in items: [SessionTreeItem]) -> Bool {
        guard let folderItem = findItem(id: folderID, in: items),
              case .folder(let folder) = folderItem else {
            return false
        }
        return containsItem(withID: itemID, in: folder.children)
    }

    private static func containsItem(withID itemID: UUID, in items: [SessionTreeItem]) -> Bool {
        for item in items {
            if item.id == itemID { return true }
            if case .folder(let folder) = item, containsItem(withID: itemID, in: folder.children) {
                return true
            }
        }
        return false
    }

    private static func parentFolderID(
        of itemID: UUID,
        in items: [SessionTreeItem],
        parentID: UUID?
    ) -> (found: Bool, parentID: UUID?) {
        for item in items {
            if item.id == itemID {
                return (true, parentID)
            }
            if case .folder(let folder) = item {
                let result = parentFolderID(of: itemID, in: folder.children, parentID: folder.id)
                if result.found {
                    return result
                }
            }
        }
        return (false, nil)
    }

    private func extractItem(
        withID id: UUID,
        from items: [SessionTreeItem]
    ) -> (item: SessionTreeItem?, tree: [SessionTreeItem]) {
        var items = items
        for index in items.indices {
            if items[index].id == id {
                let item = items.remove(at: index)
                return (item, items)
            }
            if case .folder(var folder) = items[index] {
                let result = extractItem(withID: id, from: folder.children)
                if let extracted = result.item {
                    folder.children = result.tree
                    items[index] = .folder(folder)
                    return (extracted, items)
                }
            }
        }
        return (nil, items)
    }

    private func insertItem(
        _ item: SessionTreeItem,
        parentFolderID: UUID?,
        beforeItemID: UUID?,
        in items: [SessionTreeItem]
    ) -> [SessionTreeItem] {
        guard let parentFolderID else {
            return insertItemInList(item, beforeItemID: beforeItemID, in: items)
        }
        return items.map { treeItem in
            switch treeItem {
            case .folder(var folder) where folder.id == parentFolderID:
                folder.children = insertItemInList(item, beforeItemID: beforeItemID, in: folder.children)
                return .folder(folder)
            case .folder(var folder):
                folder.children = insertItem(
                    item,
                    parentFolderID: parentFolderID,
                    beforeItemID: beforeItemID,
                    in: folder.children
                )
                return .folder(folder)
            case .session, .group:
                return treeItem
            }
        }
    }

    private func insertItemInList(
        _ item: SessionTreeItem,
        beforeItemID: UUID?,
        in list: [SessionTreeItem]
    ) -> [SessionTreeItem] {
        var list = list
        if let beforeItemID, let index = list.firstIndex(where: { $0.id == beforeItemID }) {
            list.insert(item, at: index)
        } else {
            list.append(item)
        }
        return list
    }

    private func resolveNamingConflicts(_ item: SessionTreeItem, parentFolderID: UUID?) -> SessionTreeItem {
        switch item {
        case .session(var profile):
            let siblings = siblingItems(inFolderID: parentFolderID)
            profile.name = uniqueSessionName(basedOn: profile.name, among: siblings)
            return .session(profile)
        case .folder(var folder):
            folder.name = uniqueFolderName(basedOn: folder.name)
            return .folder(folder)
        case .group(var group):
            group.name = uniqueGroupName(basedOn: group.name)
            return .group(group)
        }
    }

    static func collectSessions(in item: SessionTreeItem) -> [SessionProfile] {
        switch item {
        case .session(let profile):
            return [profile]
        case .folder(let folder):
            return folder.children.flatMap { collectSessions(in: $0) }
        case .group:
            return []
        }
    }

    func item(withID id: UUID) -> SessionTreeItem? {
        Self.findItem(id: id, in: sessionTree)
    }

    private func updateInTree(
        _ items: [SessionTreeItem],
        id: UUID,
        transform: (SessionTreeItem) -> SessionTreeItem
    ) -> [SessionTreeItem] {
        items.map { item in
            if item.id == id {
                return transform(item)
            }
            if case .folder(var folder) = item {
                folder.children = updateInTree(folder.children, id: id, transform: transform)
                return .folder(folder)
            }
            return item
        }
    }

    private func removeFromTree(_ items: [SessionTreeItem], id: UUID) -> [SessionTreeItem] {
        items.compactMap { item in
            if item.id == id { return nil }
            if case .folder(var folder) = item {
                folder.children = removeFromTree(folder.children, id: id)
                return .folder(folder)
            }
            return item
        }
    }

    static func findItem(id: UUID, in items: [SessionTreeItem]) -> SessionTreeItem? {
        for item in items {
            if item.id == id { return item }
            if case .folder(let folder) = item,
               let found = findItem(id: id, in: folder.children) {
                return found
            }
        }
        return nil
    }

    static func findSession(id: UUID, in items: [SessionTreeItem]) -> SessionProfile? {
        findSessionProfile(id: id, in: items)
    }

    static func findSessionProfile(id: UUID, in items: [SessionTreeItem]) -> SessionProfile? {
        for item in items {
            switch item {
            case .session(let profile) where profile.id == id:
                return profile
            case .folder(let folder):
                if let found = findSessionProfile(id: id, in: folder.children) {
                    return found
                }
            case .session, .group:
                continue
            }
        }
        return nil
    }

    static func findGroupMember(id memberID: UUID, in items: [SessionTreeItem]) -> (groupID: UUID, member: SessionGroupMember)? {
        for item in items {
            guard case .group(let group) = item else { continue }
            if let member = group.members.first(where: { $0.id == memberID }) {
                return (group.id, member)
            }
        }
        return nil
    }

    static func groupNames(in items: [SessionTreeItem], excludingID: UUID? = nil) -> [String] {
        items.compactMap { item in
            guard case .group(let group) = item, group.id != excludingID else { return nil }
            return group.name
        }
    }

    static func folderNames(in items: [SessionTreeItem], excludingID: UUID? = nil) -> [String] {
        var names: [String] = []
        for item in items {
            guard case .folder(let folder) = item else { continue }
            if folder.id != excludingID {
                names.append(folder.name)
            }
            names.append(contentsOf: folderNames(in: folder.children, excludingID: excludingID))
        }
        return names
    }

    private func uniqueGroupName(basedOn name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = base.isEmpty ? "New Group" : base
        if !groupNameExists(root) {
            return root
        }
        var counter = 2
        while groupNameExists("\(root) \(counter)") {
            counter += 1
        }
        return "\(root) \(counter)"
    }

    private func removeMemberFromGroupLayout(_ memberID: UUID, in node: GroupLayoutNode) -> GroupLayoutNode? {
        if node.memberID == memberID { return nil }
        guard node.children.count == 2 else { return node }
        let left = removeMemberFromGroupLayout(memberID, in: node.children[0])
        let right = removeMemberFromGroupLayout(memberID, in: node.children[1])
        switch (left, right) {
        case (nil, nil):
            return nil
        case (nil, let right?):
            return right
        case (let left?, nil):
            return left
        case (let left?, let right?):
            return GroupLayoutNode(orientation: node.orientation, children: [left, right], ratio: node.ratio)
        }
    }

    private func uniqueFolderName(basedOn name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = base.isEmpty ? "New Folder" : base
        if !folderNameExists(root) {
            return root
        }
        var counter = 2
        while folderNameExists("\(root) \(counter)") {
            counter += 1
        }
        return "\(root) \(counter)"
    }

    private func uniqueSessionName(basedOn name: String, among siblings: [SessionTreeItem]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = base.isEmpty ? "New Session" : base
        let existing = Self.sessionNames(in: siblings)
        if !existing.contains(where: { $0.compare(root, options: .caseInsensitive) == .orderedSame }) {
            return root
        }
        var counter = 2
        while existing.contains(where: { $0.compare("\(root) \(counter)", options: .caseInsensitive) == .orderedSame }) {
            counter += 1
        }
        return "\(root) \(counter)"
    }

    private func siblingItems(inFolderID folderID: UUID?) -> [SessionTreeItem] {
        guard let folderID,
              let item = Self.findItem(id: folderID, in: sessionTree),
              case .folder(let folder) = item else {
            return sessionTree
        }
        return folder.children
    }

    private func siblingContainer(forSessionID sessionID: UUID) -> [SessionTreeItem]? {
        Self.siblingContainer(forSessionID: sessionID, in: sessionTree)
    }

    static func siblingContainer(forSessionID sessionID: UUID, in items: [SessionTreeItem]) -> [SessionTreeItem]? {
        if items.contains(where: { $0.id == sessionID }) {
            return items
        }
        for item in items {
            guard case .folder(let folder) = item,
                  let found = siblingContainer(forSessionID: sessionID, in: folder.children) else {
                continue
            }
            return found
        }
        return nil
    }

    static func sessionNames(in items: [SessionTreeItem], excludingID: UUID? = nil) -> [String] {
        items.compactMap { item in
            guard case .session(let profile) = item, profile.id != excludingID else { return nil }
            return profile.name
        }
    }

    private func loadSettings() {
        let url = configTomlURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            settings = .defaults
            saveSettings()
            return
        }
        do {
            settings = try TomlConfigCodec.decode(from: url)
        } catch {
            AppLogger.shared.error("Failed to load config.toml: \(error)")
            settings = .defaults
        }
    }

    private func loadSessions() {
        let url = sessionsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            sessionTree = sampleSessionTree()
            saveSessions()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let config = try jsonDecoder.decode(SessionConfiguration.self, from: data)
            sessionTree = config.sessionTree
        } catch {
            AppLogger.shared.error("Failed to load sessions JSON: \(error)")
            sessionTree = sampleSessionTree()
        }
    }

    private func siblingIDAfter(sessionID: UUID, in siblings: [SessionTreeItem]) -> UUID? {
        guard let index = siblings.firstIndex(where: { $0.id == sessionID }),
              index + 1 < siblings.count else {
            return nil
        }
        return siblings[index + 1].id
    }

    private func insertSession(
        _ profile: SessionProfile,
        folderID: UUID,
        beforeItemID: UUID?,
        in items: [SessionTreeItem]
    ) -> [SessionTreeItem] {
        items.map { item in
            switch item {
            case .folder(var folder) where folder.id == folderID:
                folder.children = insertItemInList(.session(profile), beforeItemID: beforeItemID, in: folder.children)
                return .folder(folder)
            case .folder(var folder):
                folder.children = insertSession(profile, folderID: folderID, beforeItemID: beforeItemID, in: folder.children)
                return .folder(folder)
            case .session, .group:
                return item
            }
        }
    }

    private func sampleSessionTree() -> [SessionTreeItem] {
        [
            .folder(SessionFolder(name: "Production", children: [
                .session(SessionProfile(name: "WebServer", host: "web01.example.com", username: "admin", protocolType: .ssh)),
                .session(SessionProfile(name: "DBServer", host: "db01.example.com", username: "dba", protocolType: .ssh, sftpEnabled: true))
            ])),
            .folder(SessionFolder(name: "Network", children: [
                .session(SessionProfile(name: "Switch1", host: "10.0.0.1", username: "netops", protocolType: .ssh))
            ])),
                .session(SessionProfile(name: "Local Shell", host: "", protocolType: .local, initialDirectory: "~/idx/terminalmanager"))
        ]
    }
}
