import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var errorMessage: String?
    @Published var focusCommandBar = false
    @Published var openUserGuide = false
    @Published var showFindBar = false
    @Published var findQuery = ""
    @Published private(set) var debouncedFindQuery = ""
    @Published var pendingUpdate: UpdateChecker.UpdateInfo?
    @Published var showUpdatePrompt = false

    private var findDebounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    let configStore: ConfigStore
    var broadcastManager: BroadcastManager
    let terminalStore = TerminalSessionStore()
    let tabLifecycleManager = TabLifecycleManager()
    let tabWorkspace = TabWorkspaceState()
    let sessionLibrary = SessionLibraryState()
    private let connectionHealthMonitor = ConnectionHealthMonitor()
    @Published var updateAvailableURL: String?

    init(configStore: ConfigStore? = nil, broadcastManager: BroadcastManager? = nil) {
        self.configStore = configStore ?? ConfigStore()
        self.broadcastManager = broadcastManager ?? BroadcastManager()
        tabWorkspace.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sessionLibrary.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        tabLifecycleManager.onHibernate = { [weak self] tabID in
            self?.hibernateTab(tabID)
        }
        tabLifecycleManager.onHibernateTick = { [weak self] in
            self?.runTabHibernationCheck()
        }
        connectionHealthMonitor.onEvaluate = { [weak self] in
            self?.evaluateConnectionHealth()
        }
    }

    // MARK: - Tab workspace forwarding (TE-02)

    var tabs: [TerminalTab] { tabWorkspace.tabs }
    var selectedTabID: UUID? {
        get { tabWorkspace.selectedTabID }
        set { tabWorkspace.selectedTabID = newValue }
    }
    var splitLayouts: [UUID: SplitLayoutNode] { tabWorkspace.splitLayouts }
    var detachedTabs: [TerminalTab] { tabWorkspace.detachedTabs }
    var tabPendingReconnect: TerminalTab? {
        get { tabWorkspace.tabPendingReconnect }
        set { tabWorkspace.tabPendingReconnect = newValue }
    }
    var pendingDetachedWindowTabID: UUID? {
        get { tabWorkspace.pendingDetachedWindowTabID }
        set { tabWorkspace.pendingDetachedWindowTabID = newValue }
    }

    var connectionHealth: [UUID: TabConnectionHealth] {
        tabWorkspace.connectionHealth
    }

    var selectedTab: TerminalTab? { tabWorkspace.selectedTab }
    var stripTabs: [TerminalTab] { tabWorkspace.stripTabs }

    func stripTabID(for tabID: UUID) -> UUID? {
        tabWorkspace.stripTabID(for: tabID)
    }

    func isStripTabSelected(_ id: UUID) -> Bool {
        tabWorkspace.isStripTabSelected(id)
    }

    // MARK: - Session library forwarding (TE-02)

    var sessionTreeSelectionID: UUID? {
        get { sessionLibrary.selectionID }
        set { sessionLibrary.selectionID = newValue }
    }

    var pendingSessionTreeAction: SessionTreeAction? {
        get { sessionLibrary.pendingAction }
        set { sessionLibrary.pendingAction = newValue }
    }

    var selectedSessionTreeFolder: SessionFolder? {
        sessionLibrary.selectedFolder(using: configStore)
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
            let previousCopyOnSelect = configStore.settings.copyOnSelect
            let previousPalette = configStore.settings.ansiPalette
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
            configureSessionRecording(from: newValue)
            configureConnectionHealthMonitoring(from: newValue)
            let newAppearance = (
                newValue.terminalFontName,
                newValue.terminalFontSize,
                newValue.terminalTheme
            )
            if previousAppearance != newAppearance
                || previousCopyOnSelect != newValue.copyOnSelect
                || previousPalette != newValue.ansiPalette {
                terminalStore.configureAppearance(from: newValue)
            }
        }
    }

    var canCreateGroupFromOpenTabs: Bool {
        !tabWorkspace.tabs.isEmpty
    }

    func requestSessionTreeAction(_ action: SessionTreeAction) {
        sessionLibrary.requestAction(action)
    }

    func consumeSessionTreeAction() {
        sessionLibrary.consumeAction()
    }

    func folderIDForNewSession() -> UUID? {
        sessionLibrary.folderIDForNewSession(using: configStore)
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
        configureConnectionHealthMonitoring(from: settings)
        configureSessionRecording(from: settings)
        let skipBackgroundTasks = CommandLine.arguments.contains("-uitest")
        if settings.checkForUpdates, !skipBackgroundTasks {
            Task { await checkForUpdates(userInitiated: false) }
        }
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
        tabWorkspace.splitLayout(containing: tabID)
    }

    func hasSplitLayout(for tabID: UUID) -> Bool {
        tabWorkspace.hasSplitLayout(for: tabID)
    }

    private func setSplitLayout(_ layout: SplitLayoutNode, anchor: UUID) {
        tabWorkspace.setSplitLayout(layout, anchor: anchor)
        saveLaunchState()
    }

    private func removeTabFromSplitLayouts(_ tabID: UUID) {
        tabWorkspace.removeTabFromSplitLayouts(tabID)
        saveLaunchState()
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
        tabWorkspace.tabs.append(tab)
        connectionHealthMonitor.touchTab(tab.id)
        if let profile = tab.profile {
            SessionRecorder.shared.start(tabID: tab.id, sessionName: profile.name)
        }
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

    @discardableResult
    func openLocalTab() -> UUID {
        openTab(from: SessionProfile(name: "Local", host: "", protocolType: .local))
    }

    func closeTab(_ tabID: UUID) {
        let closingPane = tabWorkspace.tabs.first(where: { $0.id == tabID })?.isSplitPane == true
        let tabIDsToClose: Set<UUID>
        if closingPane {
            tabIDsToClose = [tabID]
            removeTabFromSplitLayouts(tabID)
        } else if let layout = tabWorkspace.splitLayout(at: tabID) {
            tabIDsToClose = layout.tabIDsInLayout()
            tabWorkspace.removeSplitLayout(anchor: tabID)
        } else {
            tabIDsToClose = [tabID]
        }

        for id in tabIDsToClose {
            let title = tabWorkspace.tabs.first(where: { $0.id == id })?.title ?? id.uuidString
            tabWorkspace.tabs.removeAll { $0.id == id }
            cleanupTabResources(tabID: id)
            AppLogger.shared.info("Closed tab '\(title)'")
        }

        if let selectedTabID, tabIDsToClose.contains(selectedTabID) {
            self.selectedTabID = stripTabs.last?.id
        }
        if tabWorkspace.tabs.isEmpty {
            tabWorkspace.clearSplitLayouts()
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
              let fromIndex = tabWorkspace.tabs.firstIndex(where: { $0.id == draggedID }) else {
            return false
        }
        var reordered = tabWorkspace.tabs
        let tab = reordered.remove(at: fromIndex)
        if let beforeID, let insertIndex = reordered.firstIndex(where: { $0.id == beforeID }) {
            reordered.insert(tab, at: insertIndex)
        } else {
            reordered.append(tab)
        }
        tabWorkspace.tabs = reordered
        saveLaunchState()
        return true
    }

    func renameTab(_ tabID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = tabWorkspace.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabWorkspace.tabs[index].title = trimmed
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
        guard let index = tabWorkspace.tabs.firstIndex(where: { $0.id == tabID }),
              !tabWorkspace.tabs[index].isSplitPane else { return }

        if let layout = tabWorkspace.splitLayout(at: tabID) {
            let paneIDs = layout.tabIDsInLayout().subtracting([tabID])
            tabWorkspace.removeSplitLayout(anchor: tabID)
            for paneID in paneIDs {
                tabWorkspace.tabs.removeAll { $0.id == paneID }
                cleanupTabResources(tabID: paneID)
            }
        } else {
            removeTabFromSplitLayouts(tabID)
        }

        var tab = tabWorkspace.tabs.remove(at: index)
        tab.isDetached = true
        tabWorkspace.detachedTabs.append(tab)
        pendingDetachedWindowTabID = tabID
        if let selectedTabID, stripTabID(for: selectedTabID) == tabID {
            self.selectedTabID = stripTabs.last?.id
        }
        saveLaunchState()
    }

    func closeDetachedTab(_ tabID: UUID) {
        guard let index = tabWorkspace.detachedTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let title = tabWorkspace.detachedTabs[index].title
        tabWorkspace.detachedTabs.remove(at: index)
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
        let allTabs = tabWorkspace.tabs + tabWorkspace.detachedTabs
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
        let title = (tabWorkspace.tabs + tabWorkspace.detachedTabs).first(where: { $0.id == tabID })?.title ?? tabID.uuidString
        broadcastManager.unregister(tabID: tabID)
        terminalStore.hibernate(tabID: tabID)
        updateTabSessionState(tabID: tabID, state: .hibernated, exitCode: nil)
        AppLogger.shared.info("Hibernated tab '\(title)'")
    }

    private func cleanupTabResources(tabID: UUID) {
        tabLifecycleManager.removeTab(tabID)
        connectionHealthMonitor.removeTab(tabID)
        tabWorkspace.removeConnectionHealth(for: tabID)
        broadcastManager.unregister(tabID: tabID)
        terminalStore.remove(tabID: tabID)
    }

    func recordTerminalOutput(tabID: UUID) {
        connectionHealthMonitor.recordOutput(tabID: tabID)
        evaluateConnectionHealth()
    }

    private func evaluateConnectionHealth() {
        for tab in tabWorkspace.tabs {
            let health = connectionHealthMonitor.health(
                for: tab.id,
                isRunning: terminalStore.isRunning(tabID: tab.id)
            )
            tabWorkspace.setConnectionHealth(health, for: tab.id)
        }
    }

    private func configureConnectionHealthMonitoring(from settings: AppSettings) {
        connectionHealthMonitor.configure(staleAfterMinutes: settings.staleTabMinutes)
        if settings.staleTabMinutes > 0 {
            connectionHealthMonitor.start()
        } else {
            connectionHealthMonitor.stop()
        }
        evaluateConnectionHealth()
    }

    func exportActiveTabTranscript(selectionOnly: Bool) {
        guard let tabID = selectedTabID else {
            errorMessage = "No tab is selected."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = selectionOnly ? "selection.txt" : "transcript.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if selectionOnly {
                try terminalStore.exportSelection(tabID: tabID, to: url)
            } else {
                try terminalStore.exportScrollback(tabID: tabID, to: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportActiveTabIOLog(redactSecrets: Bool = true) {
        guard let tab = selectedTab else {
            errorMessage = "No tab is selected."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(tab.title)-io-log.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try TerminalIOLogExporter.exportTabLog(
                tabID: tab.id,
                sessionName: tab.profile?.name ?? tab.title,
                to: url,
                redactSecrets: redactSecrets,
                settings: settings
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTabRemoteOverrides(
        tabID: UUID,
        remoteEnvironment: String?,
        remoteWorkingDirectory: String?
    ) {
        guard let index = tabWorkspace.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabWorkspace.tabs[index].remoteEnvironmentOverride = remoteEnvironment
        tabWorkspace.tabs[index].remoteWorkingDirectoryOverride = remoteWorkingDirectory
        saveLaunchState()
    }

    func addSFTPBookmark(for profileID: UUID, path: String) {
        guard var profile = configStore.sessionProfile(withID: profileID) else { return }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !profile.sftpBookmarks.contains(trimmed) else { return }
        profile.sftpBookmarks.append(trimmed)
        _ = updateSessionProfile(profile)
    }

    func revealActiveTabRecording() {
        guard let tabID = selectedTabID,
              let url = SessionRecorder.shared.recordingURL(for: tabID) else {
            errorMessage = "No session recording is available for the selected tab."
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Recording is still in progress. Close the session or wait for it to finish."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func exportActiveTabRecording() {
        guard let tabID = selectedTabID,
              let sourceURL = SessionRecorder.shared.recordingURL(for: tabID) else {
            errorMessage = "No session recording is available for the selected tab."
            return
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            errorMessage = "Recording is still in progress. Close the session or wait for it to finish."
            return
        }
        let format = SessionRecorder.shared.recordingFormat(for: tabID) ?? settings.sessionRecordingFormat
        let panel = NSSavePanel()
        if format == .asciinema, let castType = UTType(filenameExtension: "cast") {
            panel.allowedContentTypes = [castType]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.title = "Export Session Recording"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configureSessionRecording(from settings: AppSettings) {
        SessionRecorder.shared.configure(
            enabled: settings.sessionRecordingEnabled,
            format: settings.sessionRecordingFormat
        )
    }

    @discardableResult
    func checkForUpdates(userInitiated: Bool) async -> Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        if let info = await UpdateChecker.fetchUpdateInfo(
            currentVersion: version,
            repository: settings.updateRepository
        ) {
            pendingUpdate = info
            updateAvailableURL = info.downloadURL
            if userInitiated {
                openPendingUpdate()
            } else {
                showUpdatePrompt = true
            }
            return true
        }
        pendingUpdate = nil
        updateAvailableURL = nil
        if userInitiated {
            errorMessage = "You are running the latest version."
        }
        return false
    }

    func openPendingUpdate() {
        guard let urlString = pendingUpdate?.downloadURL ?? updateAvailableURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        dismissUpdatePrompt()
    }

    func dismissUpdatePrompt() {
        showUpdatePrompt = false
    }

    private func configureTabLifecycleMonitoring(from settings: AppSettings) {
        if settings.hibernateInactiveTabsMinutes > 0 {
            tabLifecycleManager.startMonitoring()
        } else {
            tabLifecycleManager.stopMonitoring()
        }
    }

    func attachTab(_ tabID: UUID) {
        guard let index = tabWorkspace.detachedTabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = tabWorkspace.detachedTabs.remove(at: index)
        tab.isDetached = false
        tabWorkspace.tabs.append(tab)
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

        if let entry = tabWorkspace.splitLayoutEntry(containing: paneToSplitID) {
            setSplitLayout(
                tabWorkspace.replacePane(containing: paneToSplitID, in: entry.layout, with: splitNode),
                anchor: entry.anchor
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
        tabWorkspace.tabs.append(tab)
        AppLogger.shared.info("Added split pane '\(profile.name)' (\(profile.protocolType.rawValue))")
        saveLaunchState()
        return tab.id
    }

    func updateTabSessionState(tabID: UUID, state: TabSessionState, exitCode: Int32? = nil) {
        if let index = tabWorkspace.tabs.firstIndex(where: { $0.id == tabID }) {
            tabWorkspace.tabs[index].sessionState = state
            tabWorkspace.tabs[index].exitCode = exitCode
            handleSessionStateSideEffects(tab: tabWorkspace.tabs[index], state: state)
        } else if let index = tabWorkspace.detachedTabs.firstIndex(where: { $0.id == tabID }) {
            tabWorkspace.detachedTabs[index].sessionState = state
            tabWorkspace.detachedTabs[index].exitCode = exitCode
            handleSessionStateSideEffects(tab: tabWorkspace.detachedTabs[index], state: state)
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
        guard tabWorkspace.tabs.contains(where: { $0.id == tabID }) else { return }
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
                  let tab = (tabWorkspace.tabs + tabWorkspace.detachedTabs).first(where: { $0.id == tabID }) else {
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
        for tab in tabWorkspace.tabs {
            if let profileID = tab.profile?.id {
                tabToProfile[tab.id] = profileID
            }
        }

        let profileIDs = stripTabs.compactMap(\.profile?.id)
        let selectedProfileID = selectedTabID.flatMap { id in
            tabWorkspace.tabs.first(where: { $0.id == id })?.profile?.id
        }

        var savedLayouts: [UUID: SplitLayoutNode] = [:]
        for (anchorTabID, layout) in tabWorkspace.splitLayouts {
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
        for index in tabWorkspace.tabs.indices where tabWorkspace.tabs[index].profile?.id == profile.id {
            tabWorkspace.tabs[index].title = profile.name
            tabWorkspace.tabs[index].profile = profile
            tabWorkspace.tabs[index].initScript = profile.initScript
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
