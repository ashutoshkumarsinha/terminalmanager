import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var tabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?
    @Published private(set) var splitLayouts: [UUID: SplitLayoutNode] = [:]
    @Published var detachedTabs: [TerminalTab] = []
    @Published var errorMessage: String?
    @Published var focusCommandBar = false
    @Published var sessionTreeSelectionID: UUID?
    @Published var pendingSessionTreeAction: SessionTreeAction?
    @Published var openUserGuide = false

    let configStore: ConfigStore
    var broadcastManager: BroadcastManager
    let terminalStore = TerminalSessionStore()

    private var cancellables = Set<AnyCancellable>()

    init(configStore: ConfigStore? = nil, broadcastManager: BroadcastManager? = nil) {
        self.configStore = configStore ?? ConfigStore()
        self.broadcastManager = broadcastManager ?? BroadcastManager()
        self.configStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var settings: AppSettings {
        get { configStore.settings }
        set {
            let previousLevel = configStore.settings.logLevel
            configStore.updateSettings(newValue)
            if newValue.logLevel != previousLevel {
                AppLogger.shared.configure(level: newValue.logLevel)
            }
        }
    }

    var selectedTab: TerminalTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var stripTabs: [TerminalTab] {
        tabs.filter { !$0.isSplitPane }
    }

    func stripTabID(for tabID: UUID) -> UUID? {
        if tabs.contains(where: { $0.id == tabID && !$0.isSplitPane }) {
            return tabID
        }
        return splitLayoutAnchor(containing: tabID)
    }

    func isStripTabSelected(_ id: UUID) -> Bool {
        guard let selectedTabID else { return false }
        return stripTabID(for: selectedTabID) == id
    }

    var selectedSessionTreeFolder: SessionFolder? {
        guard let sessionTreeSelectionID,
              let item = configStore.item(withID: sessionTreeSelectionID),
              case .folder(let folder) = item else {
            return nil
        }
        return folder
    }

    var canCreateGroupFromOpenTabs: Bool {
        !tabs.isEmpty
    }

    func requestSessionTreeAction(_ action: SessionTreeAction) {
        pendingSessionTreeAction = action
    }

    func consumeSessionTreeAction() {
        pendingSessionTreeAction = nil
    }

    func folderIDForNewSession() -> UUID? {
        guard let sessionTreeSelectionID,
              let item = configStore.item(withID: sessionTreeSelectionID) else {
            return nil
        }
        switch item {
        case .folder(let folder):
            return folder.id
        case .session:
            return ConfigStore.parentFolderID(of: sessionTreeSelectionID, in: configStore.sessionTree)
        case .group:
            return nil
        }
    }

    func bootstrap() {
        configStore.load()
        AppLogger.shared.configure(level: settings.logLevel)
        AppLogger.shared.info("Terminal Manager started (config: \(configStore.configTomlURL.path))")
        if tabs.isEmpty {
            openLocalTab()
        }
    }

    @discardableResult
    func openTab(
        from profile: SessionProfile,
        title: String? = nil,
        overrideCommand: ConnectionCommand? = nil
    ) -> UUID {
        appendTab(from: profile, title: title, overrideCommand: overrideCommand, select: true)
    }

    @discardableResult
    func openConnectionString(_ connectionString: String) -> UUID? {
        guard let profile = SessionProfile.quickConnect(from: connectionString) else {
            AppLogger.shared.warning("Could not parse connection URI: \(connectionString)")
            return nil
        }
        AppLogger.shared.info("Opening connection from URI (\(profile.protocolType.rawValue)://\(profile.host))")
        return openTab(from: profile)
    }

    func consumePendingConnectionRequests() {
        for url in AppDelegate.shared?.dequeuePendingOpenURLs() ?? [] {
            openConnectionString(url)
        }
        for arg in CommandLine.arguments.dropFirst() where ConnectionURIParser.looksLikeURI(arg) {
            openConnectionString(arg)
        }
    }

    func splitLayout(containing tabID: UUID) -> SplitLayoutNode? {
        for layout in splitLayouts.values where layout.isSplitTree && layout.tabIDsInLayout().contains(tabID) {
            return layout
        }
        return nil
    }

    func hasSplitLayout(for tabID: UUID) -> Bool {
        splitLayout(containing: tabID) != nil
    }

    private func splitLayoutAnchor(containing tabID: UUID) -> UUID? {
        for (anchor, layout) in splitLayouts where layout.isSplitTree && layout.tabIDsInLayout().contains(tabID) {
            return anchor
        }
        return nil
    }

    private func setSplitLayout(_ layout: SplitLayoutNode, anchor: UUID) {
        if layout.isSplitTree {
            splitLayouts[anchor] = layout
        } else {
            splitLayouts.removeValue(forKey: anchor)
        }
    }

    private func removeTabFromSplitLayouts(_ tabID: UUID) {
        let anchors = splitLayouts.keys.filter { splitLayouts[$0]?.tabIDsInLayout().contains(tabID) == true }
        for anchor in anchors {
            guard let layout = splitLayouts[anchor],
                  let updated = removeTabFromLayout(tabID, in: layout) else {
                splitLayouts.removeValue(forKey: anchor)
                continue
            }
            setSplitLayout(updated, anchor: anchor)
        }
    }

    @discardableResult
    private func appendTab(
        from profile: SessionProfile,
        title: String? = nil,
        overrideCommand: ConnectionCommand? = nil,
        select: Bool = true
    ) -> UUID {
        let tab = TerminalTab(
            title: title ?? profile.name,
            profile: profile,
            overrideCommand: overrideCommand,
            initScript: profile.initScript
        )
        tabs.append(tab)
        if select {
            selectedTabID = tab.id
        }
        AppLogger.shared.info("Opened tab '\(tab.title)' (\(profile.protocolType.rawValue))")
        return tab.id
    }

    func openQuickConnect(host: String, username: String, protocolType: ConnectionProtocol, port: Int?) {
        let profile = SessionProfile(
            name: host.isEmpty ? "Quick Connect" : host,
            host: host,
            port: port,
            username: username,
            protocolType: protocolType
        )
        openTab(from: profile)
    }

    func openLocalTab() {
        let profile = SessionProfile(name: "Local", host: "", protocolType: .local)
        openTab(from: profile)
    }

    func closeTab(_ tabID: UUID) {
        let closingPane = tabs.first(where: { $0.id == tabID })?.isSplitPane == true
        let tabIDsToClose: Set<UUID>
        if closingPane {
            tabIDsToClose = [tabID]
            removeTabFromSplitLayouts(tabID)
        } else if let layout = splitLayouts[tabID] {
            tabIDsToClose = layout.tabIDsInLayout()
            splitLayouts.removeValue(forKey: tabID)
        } else {
            tabIDsToClose = [tabID]
        }

        for id in tabIDsToClose {
            let title = tabs.first(where: { $0.id == id })?.title ?? id.uuidString
            tabs.removeAll { $0.id == id }
            broadcastManager.unregister(tabID: id)
            terminalStore.remove(tabID: id)
            AppLogger.shared.info("Closed tab '\(title)'")
        }

        if let selectedTabID, tabIDsToClose.contains(selectedTabID) {
            self.selectedTabID = stripTabs.last?.id
        }
        if tabs.isEmpty {
            splitLayouts.removeAll()
        }
    }

    func duplicateSelectedTab() {
        guard let selected = selectedTab, let profile = selected.profile else { return }
        openTab(from: profile)
    }

    @discardableResult
    func moveTab(withID draggedID: UUID, before beforeID: UUID?) -> Bool {
        guard draggedID != beforeID,
              let fromIndex = tabs.firstIndex(where: { $0.id == draggedID }) else {
            return false
        }
        var reordered = tabs
        let tab = reordered.remove(at: fromIndex)
        if let beforeID, let insertIndex = reordered.firstIndex(where: { $0.id == beforeID }) {
            reordered.insert(tab, at: insertIndex)
        } else {
            reordered.append(tab)
        }
        tabs = reordered
        return true
    }

    func renameTab(_ tabID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].title = trimmed
    }

    func selectNextTab() {
        let strip = stripTabs
        guard !strip.isEmpty else { return }
        guard let current = selectedTabID.flatMap({ stripTabID(for: $0) }),
              let index = strip.firstIndex(where: { $0.id == current }) else {
            selectedTabID = strip.first?.id
            return
        }
        selectedTabID = strip[(index + 1) % strip.count].id
    }

    func selectPreviousTab() {
        let strip = stripTabs
        guard !strip.isEmpty else { return }
        guard let current = selectedTabID.flatMap({ stripTabID(for: $0) }),
              let index = strip.firstIndex(where: { $0.id == current }) else {
            selectedTabID = strip.first?.id
            return
        }
        selectedTabID = strip[(index - 1 + strip.count) % strip.count].id
    }

    func detachTab(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              !tabs[index].isSplitPane else { return }

        if let layout = splitLayouts[tabID] {
            let paneIDs = layout.tabIDsInLayout().subtracting([tabID])
            splitLayouts.removeValue(forKey: tabID)
            for paneID in paneIDs {
                tabs.removeAll { $0.id == paneID }
                broadcastManager.unregister(tabID: paneID)
                terminalStore.remove(tabID: paneID)
            }
        } else {
            removeTabFromSplitLayouts(tabID)
        }

        var tab = tabs.remove(at: index)
        tab.isDetached = true
        detachedTabs.append(tab)
        if let selectedTabID, stripTabID(for: selectedTabID) == tabID {
            self.selectedTabID = stripTabs.last?.id
        }
    }

    func attachTab(_ tabID: UUID) {
        guard let index = detachedTabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = detachedTabs.remove(at: index)
        tab.isDetached = false
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func splitSelectedTab(orientation: SplitOrientation) {
        guard let selected = selectedTab else { return }
        let paneToSplitID = selected.id
        let stripAnchorID = stripTabID(for: paneToSplitID) ?? paneToSplitID
        let newProfile = SessionProfile(name: "Local", host: "", protocolType: .local)
        let newPaneID = appendSplitPane(from: newProfile)
        let splitNode = SplitLayoutNode.split(
            orientation,
            .leaf(tabID: paneToSplitID),
            .leaf(tabID: newPaneID)
        )

        if let anchor = splitLayoutAnchor(containing: paneToSplitID),
           let existing = splitLayouts[anchor] {
            setSplitLayout(
                replacePane(containing: paneToSplitID, in: existing, with: splitNode),
                anchor: anchor
            )
        } else {
            setSplitLayout(splitNode, anchor: stripAnchorID)
        }
        AppLogger.shared.info(
            "Split tab '\(selected.title)' \(orientation.rawValue) with one new local pane"
        )
    }

    @discardableResult
    private func appendSplitPane(from profile: SessionProfile) -> UUID {
        let tab = TerminalTab(
            title: profile.name,
            profile: profile,
            isSplitPane: true,
            initScript: profile.initScript
        )
        tabs.append(tab)
        AppLogger.shared.info("Added split pane '\(profile.name)' (\(profile.protocolType.rawValue))")
        return tab.id
    }

    private func replacePane(
        containing tabID: UUID,
        in node: SplitLayoutNode,
        with replacement: SplitLayoutNode
    ) -> SplitLayoutNode {
        if node.tabID == tabID {
            return replacement
        }
        guard node.children.count == 2 else { return node }
        var updated = node
        updated.children[0] = replacePane(containing: tabID, in: node.children[0], with: replacement)
        updated.children[1] = replacePane(containing: tabID, in: node.children[1], with: replacement)
        return updated
    }

    private func removeTabFromLayout(_ tabID: UUID, in node: SplitLayoutNode) -> SplitLayoutNode? {
        if node.tabID == tabID { return nil }
        guard node.children.count == 2 else { return node }
        let left = removeTabFromLayout(tabID, in: node.children[0])
        let right = removeTabFromLayout(tabID, in: node.children[1])
        switch (left, right) {
        case (nil, nil):
            return nil
        case (nil, let right?):
            return right
        case (let left?, nil):
            return left
        case (let left?, let right?):
            return SplitLayoutNode(orientation: node.orientation, children: [left, right], ratio: node.ratio)
        }
    }

    private func report(_ error: Error) {
        AppLogger.shared.error(error.localizedDescription)
        errorMessage = error.localizedDescription
    }

    func clearError() {
        errorMessage = nil
    }

    func launchSFTP(for profile: SessionProfile) {
        guard let command = ConnectionLauncher.sftpCommand(for: profile) else {
            AppLogger.shared.warning("SFTP is only available for SSH sessions")
            return
        }
        openTab(from: profile, title: "\(profile.name) (SFTP)", overrideCommand: command)
    }

    @discardableResult
    func updateSessionProfile(_ profile: SessionProfile) -> Bool {
        guard configStore.updateSession(profile) else { return false }
        for index in tabs.indices where tabs[index].profile?.id == profile.id {
            tabs[index].title = profile.name
            tabs[index].profile = profile
            tabs[index].initScript = profile.initScript
        }
        return true
    }

    func removeSessionItem(id: UUID) {
        let removedSessions = configStore.removeItem(id: id)
        AppLogger.shared.info("Removed session item \(id) (\(removedSessions.count) session(s))")
        let removedSessionIDs = Set(removedSessions.map(\.id))
        let tabIDsToClose = tabs.compactMap { tab -> UUID? in
            guard let profileID = tab.profile?.id, removedSessionIDs.contains(profileID) else { return nil }
            return tab.id
        }
        for tabID in tabIDsToClose {
            closeTab(tabID)
        }
    }

    func exportSessions(to url: URL) {
        do {
            try configStore.exportSessions(to: url)
        } catch {
            report(error)
        }
    }

    func importSessions(from url: URL) {
        do {
            try configStore.importSessions(from: url)
        } catch {
            report(error)
        }
    }

    func openGroup(_ group: SessionGroup) {
        var memberToTab: [UUID: UUID] = [:]
        var firstTabID: UUID?

        for member in group.members {
            guard let profile = ConfigStore.findSessionProfile(id: member.sessionID, in: configStore.sessionTree) else {
                continue
            }
            let tabID = appendTab(from: profile, select: false)
            memberToTab[member.id] = tabID
            if firstTabID == nil {
                firstTabID = tabID
            }
        }

        if let layout = group.layout,
           let splitLayout = GroupLayoutMapper.toSplitLayout(layout, memberToTab: memberToTab),
           let firstTabID {
            setSplitLayout(splitLayout, anchor: firstTabID)
        }

        selectedTabID = firstTabID ?? tabs.last?.id
        AppLogger.shared.info("Opened group '\(group.name)' with \(group.members.count) session(s)")
    }

    @discardableResult
    func saveCurrentTabsAsGroup(name: String) -> SessionGroup? {
        let tabsWithProfiles = tabs.compactMap { tab -> (TerminalTab, SessionProfile)? in
            guard !tab.isSplitPane, let profile = tab.profile else { return nil }
            return (tab, profile)
        }
        guard !tabsWithProfiles.isEmpty else { return nil }

        var members: [SessionGroupMember] = []
        var tabToMember: [UUID: UUID] = [:]

        for (tab, profile) in tabsWithProfiles {
            let member = SessionGroupMember(sessionID: profile.id)
            members.append(member)
            tabToMember[tab.id] = member.id
        }

        var groupLayout: GroupLayoutNode?
        if let selectedTabID,
           let layout = splitLayout(containing: selectedTabID) {
            groupLayout = GroupLayoutMapper.fromSplitLayout(layout, tabToMember: tabToMember)
        }

        let saved = configStore.saveGroup(name: name, members: members, layout: groupLayout)
        AppLogger.shared.info("Saved tab group '\(saved.name)' with \(saved.members.count) session(s)")
        return saved
    }
}
