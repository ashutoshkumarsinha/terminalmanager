import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct MainWindowConfigurator: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState

    func makeCoordinator() -> MainWindowObserver {
        MainWindowObserver()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.didAttachWindow else { return }
        configureWindow(from: nsView, coordinator: context.coordinator)
    }

    private func configureWindow(from view: NSView, coordinator: MainWindowObserver) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.title = AppInfo.displayName
            if !coordinator.didApplyLaunchSettings {
                WindowStateManager.applyLaunchSettings(to: window, settings: appState.settings)
                coordinator.markLaunchSettingsApplied()
            }
            coordinator.attach(to: window)
            coordinator.didAttachWindow = true
        }
    }
}

struct TabStripView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tabIDPendingRename: UUID?
    @State private var renameTitle = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(appState.stripTabs) { tab in
                    TabChipView(
                        tab: tab,
                        isSelected: appState.isStripTabSelected(tab.id),
                        onSelect: { appState.selectedTabID = tab.id },
                        onClose: { appState.closeTab(tab.id) },
                        onDetach: { appState.detachTab(tab.id) },
                        onRename: {
                            tabIDPendingRename = tab.id
                            renameTitle = tab.title
                        },
                        onMoveTab: { draggedID in
                            appState.moveTab(withID: draggedID, before: tab.id)
                        }
                    )
                }

                TabStripEndDropZone()

                Button {
                    appState.openLocalTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .appHelp("New Tab")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)
        .alert("Rename Tab", isPresented: Binding(
            get: { tabIDPendingRename != nil },
            set: { if !$0 { tabIDPendingRename = nil } }
        )) {
            TextField("Tab name", text: $renameTitle)
            Button("Rename") {
                if let tabID = tabIDPendingRename {
                    appState.renameTab(tabID, title: renameTitle)
                }
                tabIDPendingRename = nil
            }
            Button("Cancel", role: .cancel) {
                tabIDPendingRename = nil
            }
        } message: {
            Text("Enter a new name for this tab.")
        }
    }
}

private struct TabStripEndDropZone: View {
    @EnvironmentObject private var appState: AppState
    @State private var isDropTarget = false

    var body: some View {
        Color.clear
            .frame(width: isDropTarget ? 20 : 8, height: 24)
            .dropDestination(for: String.self) { items, _ in
                guard let draggedID = items.compactMap({ UUID(uuidString: $0) }).first else { return false }
                return appState.moveTab(withID: draggedID, before: nil)
            } isTargeted: { isDropTarget = $0 }
    }
}

private struct TabChipView: View {
    let tab: TerminalTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDetach: () -> Void
    let onRename: () -> Void
    let onMoveTab: (UUID) -> Void

    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sessionStateColor)
                .frame(width: 7, height: 7)
                .appHelp(sessionStateHelp)

            Button(action: onSelect) {
                Text(tab.title)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .appHelp("Select \(tab.title). Double-click to rename.")
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { _ in onRename() }
            )

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(isSelected ? 1 : 0.5)
            .appHelp("Close Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(chipBackground, in: Capsule())
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.compactMap({ UUID(uuidString: $0) }).first,
                  draggedID != tab.id else { return false }
            onMoveTab(draggedID)
            return true
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            Button("Rename…") { onRename() }
            Divider()
            Button("Detach Window") { onDetach() }
            Button("Close") { onClose() }
        }
    }

    private var chipBackground: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.35)
        }
        return isSelected ? Color.accentColor.opacity(0.25) : Color.clear
    }

    private var sessionStateColor: Color {
        switch tab.sessionState {
        case .running: .green
        case .idle: .gray
        case .hibernated: .orange
        case .exited: .red
        }
    }

    private var sessionStateHelp: String {
        switch tab.sessionState {
        case .running: return "Session running"
        case .idle: return "Session idle"
        case .hibernated: return "Session hibernated — select tab to reconnect"
        case .exited:
            if let exitCode = tab.exitCode {
                return "Session exited (code \(exitCode))"
            }
            return "Session exited"
        }
    }
}

struct QuickConnectBar: View {
    @EnvironmentObject private var appState: AppState
    @State private var connectionText = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("ssh://user@host:22 or host", text: $connectionText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(connect)
            Button("Connect", action: connect)
                .disabled(connectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .appHelp("Open a new tab from a connection URI or host string")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func connect() {
        let trimmed = connectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if appState.openConnectionString(trimmed) != nil {
            connectionText = ""
        }
    }
}

struct ShellCommandBar: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isFocused: Bool
    @State private var commandText = ""

    private enum Metrics {
        static let lineHeight: CGFloat = 22
        static let horizontalInset: CGFloat = 6
    }

    private var openTabIDs: [UUID] {
        appState.tabs.map(\.id)
    }

    private var targetTabIDs: [UUID] {
        switch appState.broadcastManager.target {
        case .selectedTab:
            appState.selectedTabID.map { [$0] } ?? []
        case .allTabs:
            openTabIDs
        }
    }

    private var eligibleTabIDs: [UUID] {
        appState.broadcastEligibleTabIDs(from: openTabIDs)
    }

    private var canSend: Bool {
        appState.broadcastManager.canSend(
            to: targetTabIDs,
            eligibleTabIDs: eligibleTabIDs,
            commandText: commandText
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Picker("Target", selection: $appState.broadcastManager.target) {
                ForEach(CommandTarget.allCases) { target in
                    Text(target.label).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .appHelp("Send the command to the selected tab or all open tabs")

            Menu {
                if appState.broadcastManager.commandHistory.isEmpty {
                    Text("No recent commands")
                } else {
                    ForEach(appState.broadcastManager.commandHistory, id: \.self) { entry in
                        Button(entry) {
                            commandText = entry
                        }
                    }
                }
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .appHelp("Recent commands sent from the command bar")

            Menu {
                if appState.broadcastManager.presets.isEmpty {
                    Text("No presets configured")
                } else {
                    ForEach(appState.broadcastManager.presets.keys.sorted(), id: \.self) { name in
                        Button(name) {
                            appState.broadcastManager.applyPreset(name)
                            commandText = appState.broadcastManager.commandText
                        }
                    }
                }
            } label: {
                Label("Presets", systemImage: "text.badge.star")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .appHelp("Insert a preset command")

            ZStack(alignment: .leading) {
                TextEditor(text: $commandText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: Metrics.lineHeight)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Metrics.horizontalInset)
                    .scrollIndicators(.automatic, axes: .vertical)
                    .focused($isFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.command) {
                            sendCommand()
                            return .handled
                        }
                        return .ignored
                    }

                if commandText.isEmpty {
                    Text("Send command to shell…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Metrics.horizontalInset + 4)
                        .allowsHitTesting(false)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            }

            Button("Send", action: sendCommand)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
                .appHelp("Send commands to shell (⌘Return). Use Return for a new line.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: appState.focusCommandBar) { _, shouldFocus in
            guard shouldFocus else { return }
            isFocused = true
            appState.focusCommandBar = false
        }
    }

    private func sendCommand() {
        appState.broadcastManager.commandText = commandText
        appState.broadcastManager.send(
            using: openTabIDs,
            selectedTabID: appState.selectedTabID,
            eligibleTabIDs: eligibleTabIDs,
            batchDelayMs: appState.settings.broadcastBatchDelayMs
        )
        commandText = ""
    }
}

struct SplitPaneView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                if appState.tabs.isEmpty {
                    ContentUnavailableView(
                        "No Tabs Open",
                        systemImage: "terminal",
                        description: Text("Connect from the sidebar or quick connect bar.")
                    )
                    .frame(width: size.width, height: size.height)
                } else {
                    let visibleTabIDs = workspaceVisibleTabIDs()
                    ForEach(visibleWorkspaceTabs(visibleTabIDs: visibleTabIDs)) { tab in
                        let rect = workspaceRect(for: tab.id, size: size, visibleTabIDs: visibleTabIDs)
                        TerminalHostView(tab: tab, isActive: true)
                            .id(tab.id)
                            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { reportVisibleTabs() }
        .onChange(of: appState.selectedTabID) { _, _ in reportVisibleTabs() }
        .onChange(of: appState.splitLayouts) { _, _ in reportVisibleTabs() }
    }

    private func reportVisibleTabs() {
        appState.reportMainWindowVisibleTabs(workspaceVisibleTabIDs())
    }

    private func workspaceVisibleTabIDs() -> Set<UUID> {
        if let selectedTabID = appState.selectedTabID,
           appState.hasSplitLayout(for: selectedTabID),
           let layout = appState.splitLayout(containing: selectedTabID) {
            return TerminalWorkspaceLayout.collectTabIDs(in: layout)
        }
        if let selectedTabID = appState.selectedTabID {
            return [selectedTabID]
        }
        return []
    }

    private func visibleWorkspaceTabs(visibleTabIDs: Set<UUID>) -> [TerminalTab] {
        appState.tabs.filter { visibleTabIDs.contains($0.id) }
    }

    private func workspaceRect(for tabID: UUID, size: CGSize, visibleTabIDs: Set<UUID>) -> CGRect {
        let fullBounds = CGRect(origin: .zero, size: size)
        if let selectedTabID = appState.selectedTabID,
           appState.hasSplitLayout(for: selectedTabID),
           let layout = appState.splitLayout(containing: selectedTabID),
           let rect = TerminalWorkspaceLayout.rect(for: tabID, in: layout, bounds: fullBounds) {
            return rect
        }
        if tabID == appState.selectedTabID {
            return fullBounds
        }
        return .zero
    }
}

private enum TerminalWorkspaceLayout {
    static func collectTabIDs(in node: SplitLayoutNode) -> Set<UUID> {
        if let tabID = node.tabID {
            return [tabID]
        }
        return Set(node.children.flatMap { collectTabIDs(in: $0) })
    }

    static func rect(for tabID: UUID, in node: SplitLayoutNode, bounds: CGRect) -> CGRect? {
        if let leafID = node.tabID {
            return leafID == tabID ? bounds : nil
        }
        guard node.children.count == 2, let orientation = node.orientation else { return nil }

        let ratio = node.ratio
        switch orientation {
        case .horizontal:
            let splitHeight = bounds.height * ratio
            let top = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: splitHeight)
            let bottom = CGRect(
                x: bounds.minX,
                y: bounds.minY + splitHeight,
                width: bounds.width,
                height: bounds.height - splitHeight
            )
            return rect(for: tabID, in: node.children[0], bounds: top)
                ?? rect(for: tabID, in: node.children[1], bounds: bottom)
        case .vertical:
            let splitWidth = bounds.width * ratio
            let left = CGRect(x: bounds.minX, y: bounds.minY, width: splitWidth, height: bounds.height)
            let right = CGRect(
                x: bounds.minX + splitWidth,
                y: bounds.minY,
                width: bounds.width - splitWidth,
                height: bounds.height
            )
            return rect(for: tabID, in: node.children[0], bounds: left)
                ?? rect(for: tabID, in: node.children[1], bounds: right)
        }
    }
}

struct DetachedWindowView: View {
    @EnvironmentObject private var appState: AppState
    let tabID: UUID

    var body: some View {
        if let tab = appState.detachedTabs.first(where: { $0.id == tabID }) {
            TerminalHostView(tab: tab)
                .background(DetachedWindowConfigurator(tabID: tabID, onWindowClose: {
                    appState.closeDetachedTab(tabID)
                }))
                .onAppear { appState.reportDetachedTabVisible(tabID, isVisible: true) }
                .onDisappear { appState.reportDetachedTabVisible(tabID, isVisible: false) }
                .toolbar {
                    ToolbarItem {
                        Button("Reattach") {
                            appState.attachTab(tabID)
                        }
                        .appHelp("Move this session back into the main window")
                    }
                }
        }
    }
}

private struct DetachedWindowConfigurator: NSViewRepresentable {
    let tabID: UUID
    var onWindowClose: (() -> Void)?

    func makeCoordinator() -> DetachedWindowObserver {
        DetachedWindowObserver(tabID: tabID, onWindowClose: onWindowClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        attachWindow(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attachWindow(from: nsView, coordinator: context.coordinator)
    }

    private func attachWindow(from view: NSView, coordinator: DetachedWindowObserver) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            coordinator.attach(to: window)
        }
    }
}

final class DetachedWindowObserver: NSObject {
    private let tabID: UUID
    private var onWindowClose: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private weak var window: NSWindow?
    private var didApplyLaunchSettings = false
    private var persistWorkItem: DispatchWorkItem?

    init(tabID: UUID, onWindowClose: (() -> Void)? = nil) {
        self.tabID = tabID
        self.onWindowClose = onWindowClose
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        if !didApplyLaunchSettings {
            WindowStateManager.applyDetachedLaunchSettings(to: window, tabID: tabID)
            didApplyLaunchSettings = true
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.persistWindowState()
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                self?.persistWindowState()
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.onWindowClose?()
            }
        ]
    }

    private func persistWindowState() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else { return }
            WindowStateManager.saveDetached(from: window, tabID: self.tabID)
        }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func detach() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        window = nil
    }

    deinit {
        detach()
    }
}

struct TerminalFindBar: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in terminal…", text: $appState.findQuery)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { appState.findNextInSelectedTab() }
                .onChange(of: appState.findQuery) { _, newValue in
                    appState.scheduleFindDebounce(from: newValue)
                }
            Button("Previous") { appState.findPreviousInSelectedTab() }
                .disabled(appState.debouncedFindQuery.isEmpty)
            Button("Next") { appState.findNextInSelectedTab() }
                .disabled(appState.debouncedFindQuery.isEmpty)
            Button {
                appState.showFindBar = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .onAppear { isFocused = true }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showSidebar: Bool = true
    @State private var showCommandBar: Bool = true
    @State private var showTooltips: Bool = true
    @State private var broadcastEnabled: Bool = true
    @State private var confirmOnExit: Bool = false
    @State private var singleInstance: Bool = false
    @State private var startMaximized: Bool = false
    @State private var restoreWindowPosition: Bool = true
    @State private var restoreTabsOnLaunch: Bool = false
    @State private var autoReconnect: Bool = true
    @State private var sessionsFile: String = "sessions.json"
    @State private var syncSessionsPath: String = ""
    @State private var logLevel: LogLevel = .info
    @State private var logTerminalIO: Bool = true
    @State private var terminalIOMaxMB: Int = 50
    @State private var terminalFontName: String = "Menlo"
    @State private var terminalFontSize: Double = 12
    @State private var terminalTheme: TerminalTheme = .system
    @State private var maxScrollbackLines: Int = 10_000
    @State private var hibernateInactiveTabsMinutes: Int = 30
    @State private var terminalIOMetadataOnly: Bool = false
    @State private var exportRedactSecrets: Bool = true
    @State private var templates: [SessionTemplate] = []
    @State private var passphrasePrompt: PassphrasePrompt?

    var body: some View {
        Form {
            Section("Interface") {
                Toggle("Show Session Sidebar", isOn: $showSidebar)
                Toggle("Show Command Bar", isOn: $showCommandBar)
                Toggle("Show Tooltips", isOn: $showTooltips)
                Toggle("Broadcast Commands", isOn: $broadcastEnabled)
                Toggle("Confirm on Quit", isOn: $confirmOnExit)
            }

            Section("Window") {
                Toggle("Single Instance", isOn: $singleInstance)
                Toggle("Start Maximized", isOn: $startMaximized)
                Toggle("Restore Window Position", isOn: $restoreWindowPosition)
                Toggle("Restore Tabs on Launch", isOn: $restoreTabsOnLaunch)
                Toggle("Auto-Reconnect Prompt", isOn: $autoReconnect)
            }

            Section("Terminal") {
                TextField("Font Name", text: $terminalFontName)
                TextField("Font Size", value: $terminalFontSize, format: .number)
                Picker("Theme", selection: $terminalTheme) {
                    Text("System").tag(TerminalTheme.system)
                    Text("Light").tag(TerminalTheme.light)
                    Text("Dark").tag(TerminalTheme.dark)
                }
                Stepper(value: $maxScrollbackLines, in: 500...100_000, step: 500) {
                    Text("Scrollback limit: \(maxScrollbackLines) lines")
                }
            }

            Section("Performance") {
                Stepper(value: $hibernateInactiveTabsMinutes, in: 0...240, step: 5) {
                    if hibernateInactiveTabsMinutes == 0 {
                        Text("Tab hibernation: off")
                    } else {
                        Text("Hibernate inactive tabs after \(hibernateInactiveTabsMinutes) min")
                    }
                }
            }

            Section("Configuration Files") {
                LabeledContent("App config") {
                    Text(appState.configStore.configTomlURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                TextField("Sessions JSON file", text: $sessionsFile)
                TextField("Sync sessions path (optional)", text: $syncSessionsPath)
                LabeledContent("Resolved sessions path") {
                    Text(FileLocations.sessionsURL(for: sessionsFile).path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Logs directory") {
                    Text(FileLocations.logsDirectory.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section("Logging") {
                Picker("Level", selection: $logLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.label.capitalized).tag(level)
                    }
                }
                Toggle("Log Terminal I/O", isOn: $logTerminalIO)
                Toggle("Terminal I/O metadata only", isOn: $terminalIOMetadataOnly)
                    .disabled(!logTerminalIO)
                Stepper(value: $terminalIOMaxMB, in: 1...500) {
                    Text("Terminal I/O log limit: \(terminalIOMaxMB) MB")
                }
            }

            Section("Session Templates") {
                if templates.isEmpty {
                    Text("No templates configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(templates) { template in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text("\(template.protocolType.displayName) · \(template.username.isEmpty ? "no user" : template.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Sessions") {
                Toggle("Redact secrets on export", isOn: $exportRedactSecrets)
                Button("Export Sessions JSON…") { exportSessions() }
                Button("Import Sessions JSON…") { importSessions() }
                Button("Export Encrypted Backup…") {
                    passphrasePrompt = PassphrasePrompt(mode: .exportBackup)
                }
                Button("Import Encrypted Backup…") {
                    passphrasePrompt = PassphrasePrompt(mode: .importBackup)
                }
            }

        }
        .padding()
        .frame(width: 560)
        .onAppear { applySettingsFromAppState() }
        .onDisappear { persistSettingsToAppState() }
        .sheet(item: $passphrasePrompt) { prompt in
            PassphrasePromptView(prompt: prompt) { passphrase in
                switch prompt.mode {
                case .exportBackup:
                    exportEncryptedBackup(passphrase: passphrase)
                case .importBackup:
                    importEncryptedBackup(passphrase: passphrase)
                }
            }
        }
    }

    private func applySettingsFromAppState() {
        let settings = appState.settings
        showSidebar = settings.showSidebar
        showCommandBar = settings.showCommandBar
        showTooltips = settings.showTooltips
        broadcastEnabled = settings.broadcastEnabled
        confirmOnExit = settings.confirmOnExit
        singleInstance = settings.singleInstance
        startMaximized = settings.startMaximized
        restoreWindowPosition = settings.restoreWindowPosition
        restoreTabsOnLaunch = settings.restoreTabsOnLaunch
        autoReconnect = settings.autoReconnect
        sessionsFile = settings.sessionsFile
        syncSessionsPath = settings.syncSessionsPath ?? ""
        logLevel = settings.logLevel
        logTerminalIO = settings.logTerminalIO
        terminalIOMaxMB = settings.terminalIOMaxMB
        terminalFontName = settings.terminalFontName
        terminalFontSize = settings.terminalFontSize
        terminalTheme = settings.terminalTheme
        maxScrollbackLines = settings.maxScrollbackLines
        hibernateInactiveTabsMinutes = settings.hibernateInactiveTabsMinutes
        terminalIOMetadataOnly = settings.terminalIOMetadataOnly
        templates = SessionTemplateStore.allTemplates(from: settings)
    }

    private func persistSettingsToAppState() {
        var settings = appState.settings
        settings.showSidebar = showSidebar
        settings.showCommandBar = showCommandBar
        settings.showTooltips = showTooltips
        settings.broadcastEnabled = broadcastEnabled
        settings.confirmOnExit = confirmOnExit
        settings.singleInstance = singleInstance
        settings.startMaximized = startMaximized
        settings.restoreWindowPosition = restoreWindowPosition
        settings.restoreTabsOnLaunch = restoreTabsOnLaunch
        settings.autoReconnect = autoReconnect
        settings.sessionsFile = sessionsFile
        let syncPath = syncSessionsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.syncSessionsPath = syncPath.isEmpty ? nil : syncPath
        settings.logLevel = logLevel
        settings.logTerminalIO = logTerminalIO
        settings.terminalIOMaxMB = terminalIOMaxMB
        settings.terminalFontName = terminalFontName
        settings.terminalFontSize = terminalFontSize
        settings.terminalTheme = terminalTheme
        settings.maxScrollbackLines = maxScrollbackLines
        settings.hibernateInactiveTabsMinutes = hibernateInactiveTabsMinutes
        settings.terminalIOMetadataOnly = terminalIOMetadataOnly
        appState.settings = settings
    }

    private func exportSessions() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "sessions.json"
        if panel.runModal() == .OK, let url = panel.url {
            appState.exportSessions(to: url, redactSecrets: exportRedactSecrets)
        }
    }

    private func importSessions() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.importSessions(from: url)
            templates = SessionTemplateStore.allTemplates(from: appState.settings)
        }
    }

    private func exportEncryptedBackup(passphrase: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "terminal-manager-backup.tmbk"
        if panel.runModal() == .OK, let url = panel.url {
            appState.exportEncryptedBackup(to: url, passphrase: passphrase)
        }
    }

    private func importEncryptedBackup(passphrase: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            appState.importEncryptedBackup(from: url, passphrase: passphrase)
            applySettingsFromAppState()
        }
    }
}

private struct PassphrasePrompt: Identifiable {
    enum Mode {
        case exportBackup
        case importBackup
    }

    let id = UUID()
    let mode: Mode
}

private struct PassphrasePromptView: View {
    @Environment(\.dismiss) private var dismiss
    let prompt: PassphrasePrompt
    let onSubmit: (String) -> Void

    @State private var passphrase = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Passphrase", text: $passphrase)
            }
            .navigationTitle(prompt.mode == .exportBackup ? "Export Backup" : "Import Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        onSubmit(passphrase)
                        dismiss()
                    }
                    .disabled(passphrase.isEmpty)
                }
            }
        }
        .frame(width: 360, height: 140)
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SessionSidebarView()
                .frame(minWidth: 220)
        } detail: {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    QuickConnectBar()
                    Divider()
                    if appState.settings.showCommandBar {
                        ShellCommandBar()
                        Divider()
                    }
                    TabStripView()
                    Divider()
                    SplitPaneView()
                }

                if appState.showFindBar {
                    TerminalFindBar()
                        .padding(.top, 8)
                }

                if let message = appState.configStore.backgroundTaskMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(message)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(AppInfo.displayName)
        .background(MainWindowConfigurator())
        .onAppear {
            columnVisibility = appState.settings.showSidebar ? .all : .detailOnly
        }
        .onChange(of: appState.settings.showSidebar) { _, showSidebar in
            columnVisibility = showSidebar ? .all : .detailOnly
        }
        .onChange(of: appState.pendingDetachedWindowTabID) { _, tabID in
            guard let tabID else { return }
            openWindow(id: "detached", value: tabID)
            appState.pendingDetachedWindowTabID = nil
        }
        .onChange(of: appState.openUserGuide) { _, open in
            guard open else { return }
            openWindow(id: "userGuide")
            appState.openUserGuide = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .openUserGuideRequested)) { _ in
            openWindow(id: "userGuide")
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    appState.splitSelectedTab(orientation: .horizontal)
                } label: {
                    Label("Split Horizontal", systemImage: "rectangle.split.1x2")
                }
                .appHelp("Split the selected tab into top and bottom panes")

                Button {
                    appState.splitSelectedTab(orientation: .vertical)
                } label: {
                    Label("Split Vertical", systemImage: "rectangle.split.2x1")
                }
                .appHelp("Split the selected tab into left and right panes")

                Button {
                    appState.duplicateSelectedTab()
                } label: {
                    Label("Duplicate Tab", systemImage: "plus.square.on.square")
                }
                .appHelp("Open a copy of the selected tab (⌘D)")
            }
        }
        .alert("Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.clearError() } }
        )) {
            Button("OK", role: .cancel) {
                appState.clearError()
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .alert(
            "Reconnect Session?",
            isPresented: Binding(
                get: { appState.tabPendingReconnect != nil },
                set: { if !$0 { appState.dismissReconnectPrompt() } }
            )
        ) {
            Button("Reconnect") {
                if let tab = appState.tabPendingReconnect {
                    appState.reconnectTab(tab.id)
                }
            }
            Button("Dismiss", role: .cancel) {
                appState.dismissReconnectPrompt()
            }
        } message: {
            if let tab = appState.tabPendingReconnect {
                Text("\"\(tab.title)\" has disconnected.")
            }
        }
    }
}
