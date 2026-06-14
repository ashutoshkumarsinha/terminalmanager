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
    @Published var showFindBar = false
    @Published var findQuery = ""
    @Published private(set) var debouncedFindQuery = ""
    @Published var tabPendingReconnect: TerminalTab?
    @Published var pendingDetachedWindowTabID: UUID?

    private var findDebounceTask: Task<Void, Never>?

    let configStore: ConfigStore
    var broadcastManager: BroadcastManager
    let terminalStore = TerminalSessionStore()
    let tabLifecycleManager = TabLifecycleManager()

    init(configStore: ConfigStore? = nil, broadcastManager: BroadcastManager? = nil) {
        self.configStore = configStore ?? ConfigStore()
        self.broadcastManager = broadcastManager ?? BroadcastManager()
        tabLifecycleManager.onHibernate = { [weak self] tabID in
            self?.hibernateTab(tabID)
        }
        tabLifecycleManager.onHibernateTick = { [weak self] in
            self?.runTabHibernationCheck()
        }
    }

    var settings: AppSettings {
        get { configStore.settings }
        set {
            let previousLevel = configStore.settings.logLevel
            let previousAppearance = (
                configStore.settings.terminalFontName,
                configStore.settings.terminalFontSize,
                configStore.settings.terminalTheme
            )
            configStore.updateSettings(newValue)
            if newValue.logLevel != previousLevel {
                AppLogger.shared.configure(level: newValue.logLevel)
            }
            TerminalIOLogger.shared.configure(
                enabled: newValue.logTerminalIO,
                maxMB: newValue.terminalIOMaxMB,
                metadataOnly: newValue.terminalIOMetadataOnly
            )
            configureTabLifecycleMonitoring(from: newValue)
            let newAppearance = (
                newValue.terminalFontName,
                newValue.terminalFontSize,
                newValue.terminalTheme
            )
            if previousAppearance != newAppearance {
                terminalStore.configureAppearance(from: newValue)
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
            return configStore.parentFolderID(of: sessionTreeSelectionID)
        case .group:
            return nil
        }
    }

    func bootstrap() {
        configStore.load()
        AppLogger.shared.configure(level: settings.logLevel)
        TerminalIOLogger.shared.configure(
            enabled: settings.logTerminalIO,
            maxMB: settings.terminalIOMaxMB,
            metadataOnly: settings.terminalIOMetadataOnly
        )
        terminalStore.configureAppearance(from: settings)
        configureTabLifecycleMonitoring(from: settings)
        configStore.onSessionsLoaded = { [weak self] in
            self?.finishBootstrapAfterSessionsLoad()
        }
        AppLogger.shared.info("Terminal Manager started (config: \(configStore.configTomlURL.path))")
        AppDelegate.shared?.onTerminateFlush = { [weak self] in
            self?.flushPersistedState()
        }
        if tabs.isEmpty {
            if settings.restoreTabsOnLaunch {
                if settings.deferSessionsLoad && !configStore.sessionsAreLoaded {
                    pendingLaunchStateRestore = true
                    configStore.loadSessionsIfNeeded()
                } else {
                    restoreTabsFromLaunchState()
                }
            } else {
                openLocalTab()
            }
        }
    }

    private var pendingLaunchStateRestore = false

    private func finishBootstrapAfterSessionsLoad() {
        guard pendingLaunchStateRestore, tabs.isEmpty else { return }
        pendingLaunchStateRestore = false
        restoreTabsFromLaunchState()
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
        saveLaunchState()
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
        saveLaunchState()
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
            cleanupTabResources(tabID: id)
            AppLogger.shared.info("Closed tab '\(title)'")
        }

        if let selectedTabID, tabIDsToClose.contains(selectedTabID) {
            self.selectedTabID = stripTabs.last?.id
        }
        if tabs.isEmpty {
            splitLayouts.removeAll()
        }
        saveLaunchState()
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
        saveLaunchState()
        return true
    }

    func renameTab(_ tabID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].title = trimmed
        saveLaunchState()
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
                cleanupTabResources(tabID: paneID)
            }
        } else {
            removeTabFromSplitLayouts(tabID)
        }

        var tab = tabs.remove(at: index)
        tab.isDetached = true
        detachedTabs.append(tab)
        pendingDetachedWindowTabID = tabID
        if let selectedTabID, stripTabID(for: selectedTabID) == tabID {
            self.selectedTabID = stripTabs.last?.id
        }
        saveLaunchState()
    }

    func closeDetachedTab(_ tabID: UUID) {
        guard let index = detachedTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let title = detachedTabs[index].title
        detachedTabs.remove(at: index)
        cleanupTabResources(tabID: tabID)
        AppLogger.shared.info("Closed detached tab '\(title)'")
    }

    func reportMainWindowVisibleTabs(_ ids: Set<UUID>) {
        tabLifecycleManager.updateMainWindowVisibleTabs(ids)
    }

    func reportDetachedTabVisible(_ tabID: UUID, isVisible: Bool) {
        tabLifecycleManager.updateDetachedVisibleTab(tabID, isVisible: isVisible)
    }

    func runTabHibernationCheck() {
        let minutes = settings.hibernateInactiveTabsMinutes
        guard minutes > 0 else { return }
        let allTabs = tabs + detachedTabs
        var runningTabIDs = Set(allTabs.filter { $0.sessionState == .running }.map(\.id))
        for tab in allTabs where terminalStore.isRunning(tabID: tab.id) {
            runningTabIDs.insert(tab.id)
        }
        tabLifecycleManager.runHibernationCheck(
            tabIDs: allTabs.map(\.id),
            runningTabIDs: runningTabIDs,
            inactivityMinutes: minutes
        )
    }

    func hibernateTab(_ tabID: UUID) {
        guard terminalStore.isRunning(tabID: tabID) || terminalStore.hasTerminal(tabID: tabID) else { return }
        let title = (tabs + detachedTabs).first(where: { $0.id == tabID })?.title ?? tabID.uuidString
        broadcastManager.unregister(tabID: tabID)
        terminalStore.hibernate(tabID: tabID)
        updateTabSessionState(tabID: tabID, state: .hibernated, exitCode: nil)
        AppLogger.shared.info("Hibernated tab '\(title)'")
    }

    private func cleanupTabResources(tabID: UUID) {
        tabLifecycleManager.removeTab(tabID)
        broadcastManager.unregister(tabID: tabID)
        terminalStore.remove(tabID: tabID)
    }

    private func configureTabLifecycleMonitoring(from settings: AppSettings) {
        if settings.hibernateInactiveTabsMinutes > 0 {
            tabLifecycleManager.startMonitoring()
        } else {
            tabLifecycleManager.stopMonitoring()
        }
    }

    func attachTab(_ tabID: UUID) {
        guard let index = detachedTabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = detachedTabs.remove(at: index)
        tab.isDetached = false
        tabs.append(tab)
        selectedTabID = tab.id
        saveLaunchState()
    }

    func splitSelectedTab(orientation: SplitOrientation) {
        guard let selected = selectedTab,
              let sourceProfile = selected.profile else { return }
        let paneToSplitID = selected.id
        let stripAnchorID = stripTabID(for: paneToSplitID) ?? paneToSplitID
        var duplicateProfile = sourceProfile
        duplicateProfile.id = UUID()
        duplicateProfile.name = "\(sourceProfile.name) (split)"
        let newPaneID = appendSplitPane(from: duplicateProfile)
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
            "Split tab '\(selected.title)' \(orientation.rawValue) with duplicated profile"
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
        saveLaunchState()
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

    func updateTabSessionState(tabID: UUID, state: TabSessionState, exitCode: Int32? = nil) {
        if let index = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[index].sessionState = state
            tabs[index].exitCode = exitCode
            handleSessionStateSideEffects(tab: tabs[index], state: state)
        } else if let index = detachedTabs.firstIndex(where: { $0.id == tabID }) {
            detachedTabs[index].sessionState = state
            detachedTabs[index].exitCode = exitCode
            handleSessionStateSideEffects(tab: detachedTabs[index], state: state)
        }
        saveLaunchState()
    }

    private func handleSessionStateSideEffects(tab: TerminalTab, state: TabSessionState) {
        if state == .exited,
           settings.autoReconnect,
           tab.profile?.protocolType != .local {
            tabPendingReconnect = tab
        }
    }

    func reconnectTab(_ tabID: UUID) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        terminalStore.remove(tabID: tabID)
        updateTabSessionState(tabID: tabID, state: .idle, exitCode: nil)
        tabPendingReconnect = nil
        objectWillChange.send()
    }

    func dismissReconnectPrompt() {
        tabPendingReconnect = nil
    }

    func findNextInSelectedTab() {
        guard let tabID = selectedTabID, !debouncedFindQuery.isEmpty else { return }
        _ = terminalStore.findNext(tabID: tabID, query: debouncedFindQuery, searchFromEnd: true)
    }

    func findPreviousInSelectedTab() {
        guard let tabID = selectedTabID, !debouncedFindQuery.isEmpty else { return }
        _ = terminalStore.findPrevious(tabID: tabID, query: debouncedFindQuery)
    }

    func scheduleFindDebounce(from query: String) {
        findDebounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedFindQuery = ""
            return
        }
        findDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(settings.findDebounceMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            debouncedFindQuery = trimmed
        }
    }

    func broadcastEligibleTabIDs(from tabIDs: [UUID]) -> [UUID] {
        tabIDs.filter { tabID in
            guard broadcastManager.hasHandler(for: tabID),
                  let tab = (tabs + detachedTabs).first(where: { $0.id == tabID }) else {
                return false
            }
            switch tab.sessionState {
            case .running, .idle: return true
            case .exited, .hibernated: return false
            }
        }
    }

    func saveLaunchState(immediate: Bool = false) {
        guard settings.restoreTabsOnLaunch else {
            PersistenceCoordinator.clearLaunchState()
            return
        }

        let state = buildLaunchState()
        if immediate {
            PersistenceCoordinator.flushLaunchState(with: state)
        } else {
            PersistenceCoordinator.scheduleLaunchStateSave(
                state,
                debounceMs: settings.launchStateDebounceMs
            )
        }
    }

    func flushPersistedState() {
        saveLaunchState(immediate: true)
        configStore.flushPendingSaves()
    }

    private func buildLaunchState() -> LaunchState {
        var tabToProfile: [UUID: UUID] = [:]
        for tab in tabs {
            if let profileID = tab.profile?.id {
                tabToProfile[tab.id] = profileID
            }
        }

        let profileIDs = stripTabs.compactMap(\.profile?.id)
        let selectedProfileID = selectedTabID.flatMap { id in
            tabs.first(where: { $0.id == id })?.profile?.id
        }

        var savedLayouts: [UUID: SplitLayoutNode] = [:]
        for (anchorTabID, layout) in splitLayouts {
            guard let anchorProfileID = tabToProfile[anchorTabID] else { continue }
            savedLayouts[anchorProfileID] = mapLayoutTabIDs(layout, using: { tabToProfile[$0] ?? $0 })
        }

        return LaunchState(
            tabProfileIDs: profileIDs,
            selectedTabProfileID: selectedProfileID,
            splitLayouts: savedLayouts
        )
    }

    private func restoreTabsFromLaunchState() {
        guard let state = LaunchStateStore.load(), !state.tabProfileIDs.isEmpty else {
            openLocalTab()
            return
        }

        if settings.staggerTabRestore {
            Task { @MainActor in
                await restoreTabsFromLaunchStateStaggered(state)
            }
        } else {
            restoreTabsFromLaunchStateImmediate(state)
        }
    }

    private func restoreTabsFromLaunchStateImmediate(_ state: LaunchState) {
        var profileToTab = openRestoredTabs(profileIDs: state.tabProfileIDs, select: false)
        guard !profileToTab.isEmpty else {
            openLocalTab()
            return
        }
        applyRestoredSplitLayouts(state: state, profileToTab: &profileToTab)
        selectRestoredTab(state: state, profileToTab: profileToTab)
        AppLogger.shared.info("Restored \(profileToTab.count) tab(s) from launch state")
    }

    private func restoreTabsFromLaunchStateStaggered(_ state: LaunchState) async {
        var profileToTab: [UUID: UUID] = [:]
        let profileIDs = state.tabProfileIDs
        let batchSize = max(1, settings.staggerTabRestoreBatchSize)
        var index = 0

        while index < profileIDs.count {
            let end = min(index + batchSize, profileIDs.count)
            for profileID in profileIDs[index ..< end] {
                guard let profile = configStore.sessionProfile(withID: profileID) else { continue }
                let tabID = appendTab(from: profile, select: false)
                profileToTab[profileID] = tabID
            }
            index = end
            await Task.yield()
        }

        guard !profileToTab.isEmpty else {
            openLocalTab()
            return
        }

        applyRestoredSplitLayouts(state: state, profileToTab: &profileToTab)
        selectRestoredTab(state: state, profileToTab: profileToTab)
        AppLogger.shared.info("Restored \(profileToTab.count) tab(s) from launch state (staggered)")
    }

    private func openRestoredTabs(profileIDs: [UUID], select: Bool) -> [UUID: UUID] {
        var profileToTab: [UUID: UUID] = [:]
        for profileID in profileIDs {
            guard let profile = configStore.sessionProfile(withID: profileID) else { continue }
            let tabID = appendTab(from: profile, select: select)
            profileToTab[profileID] = tabID
        }
        return profileToTab
    }

    private func applyRestoredSplitLayouts(state: LaunchState, profileToTab: inout [UUID: UUID]) {
        for (anchorProfileID, layout) in state.splitLayouts {
            guard let anchorTabID = profileToTab[anchorProfileID] else { continue }
            let restoredLayout = restoreSplitLayoutNode(layout, profileToTab: &profileToTab)
            setSplitLayout(restoredLayout, anchor: anchorTabID)
        }
    }

    private func selectRestoredTab(state: LaunchState, profileToTab: [UUID: UUID]) {
        if let selectedProfileID = state.selectedTabProfileID,
           let tabID = profileToTab[selectedProfileID] {
            selectedTabID = tabID
        } else {
            selectedTabID = stripTabs.first?.id
        }
    }

    private func restoreSplitLayoutNode(
        _ node: SplitLayoutNode,
        profileToTab: inout [UUID: UUID]
    ) -> SplitLayoutNode {
        if let profileID = node.tabID {
            if let existingTabID = profileToTab[profileID] {
                return .leaf(tabID: existingTabID)
            }
            guard let profile = configStore.sessionProfile(withID: profileID) else {
                return .leaf(tabID: profileID)
            }
            let paneID = appendSplitPane(from: profile)
            profileToTab[profileID] = paneID
            return .leaf(tabID: paneID)
        }
        return SplitLayoutNode(
            orientation: node.orientation,
            children: node.children.map { restoreSplitLayoutNode($0, profileToTab: &profileToTab) },
            ratio: node.ratio
        )
    }

    private func mapLayoutTabIDs(_ node: SplitLayoutNode, using transform: (UUID) -> UUID) -> SplitLayoutNode {
        if let tabID = node.tabID {
            return .leaf(tabID: transform(tabID))
        }
        return SplitLayoutNode(
            orientation: node.orientation,
            children: node.children.map { mapLayoutTabIDs($0, using: transform) },
            ratio: node.ratio
        )
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

    func exportSessions(to url: URL, redactSecrets: Bool = false) {
        do {
            try configStore.exportSessions(to: url, redactSecrets: redactSecrets)
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

    func exportEncryptedBackup(to url: URL, passphrase: String) {
        Task {
            do {
                try await configStore.exportEncryptedBackup(to: url, passphrase: passphrase)
            } catch {
                report(error)
            }
        }
    }

    func importEncryptedBackup(from url: URL, passphrase: String) {
        Task {
            do {
                try await configStore.importEncryptedBackup(from: url, passphrase: passphrase)
            } catch {
                report(error)
            }
        }
    }

    func testConnection(for profile: SessionProfile) async -> ConnectionTester.TestResult {
        await ConnectionTester.testConnection(for: profile)
    }

    @discardableResult
    func createEmptyGroup(name: String = "New Group") -> SessionGroup {
        configStore.createEmptyGroup(name: name)
    }

    @discardableResult
    func updateGroupLayout(for groupID: UUID) -> Bool {
        configStore.updateGroupLayout(
            groupID: groupID,
            from: tabs,
            splitLayouts: splitLayouts,
            selectedTabID: selectedTabID
        )
    }

    @discardableResult
    func duplicateSessionToFolder(sessionID: UUID, folderID: UUID) -> SessionProfile? {
        configStore.duplicateSessionToFolder(sessionID: sessionID, folderID: folderID)
    }

    func openGroup(_ group: SessionGroup) {
        var memberToTab: [UUID: UUID] = [:]
        var firstTabID: UUID?

        for member in group.members {
            guard let profile = configStore.sessionProfile(withID: member.sessionID) else {
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
