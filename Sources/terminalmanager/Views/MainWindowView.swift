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
}

struct ShellCommandBar: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isFocused: Bool

    private enum Metrics {
        static let lineHeight: CGFloat = 22
        static let horizontalInset: CGFloat = 6
    }

    private var commandBinding: Binding<String> {
        Binding(
            get: { appState.broadcastManager.commandText },
            set: { appState.broadcastManager.commandText = $0 }
        )
    }

    private var commandText: String {
        appState.broadcastManager.commandText
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

    private var canSend: Bool {
        appState.broadcastManager.canSend(to: targetTabIDs)
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

            ZStack(alignment: .leading) {
                TextEditor(text: commandBinding)
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
        appState.broadcastManager.send(using: openTabIDs, selectedTabID: appState.selectedTabID)
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
                    ForEach(sortedTabs(visibleTabIDs: visibleTabIDs)) { tab in
                        let rect = workspaceRect(for: tab.id, size: size)
                        let isVisible = visibleTabIDs.contains(tab.id)
                        TerminalHostView(tab: tab, isActive: true)
                            .id(tab.id)
                            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                            .offset(x: rect.minX, y: rect.minY)
                            .opacity(isVisible ? 1 : 0)
                            .allowsHitTesting(isVisible)
                            .accessibilityHidden(!isVisible)
                            .zIndex(isVisible ? 1 : 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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

    private func sortedTabs(visibleTabIDs: Set<UUID>) -> [TerminalTab] {
        appState.tabs.sorted { lhs, rhs in
            let lhsVisible = visibleTabIDs.contains(lhs.id)
            let rhsVisible = visibleTabIDs.contains(rhs.id)
            if lhsVisible != rhsVisible {
                return !lhsVisible
            }
            return false
        }
    }

    private func workspaceRect(for tabID: UUID, size: CGSize) -> CGRect {
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

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var ghosttyPath: String = ""
    @State private var backend: TerminalBackend = .embedded
    @State private var showSidebar: Bool = true
    @State private var sessionsFile: String = "sessions.json"
    @State private var logLevel: LogLevel = .info

    var body: some View {
        Form {
            Section("External Terminal") {
                Picker("Rendering Mode", selection: $backend) {
                    ForEach(TerminalBackend.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .appHelp("Embedded runs terminals inside this app; Ghostty opens external windows")
                TextField("Ghostty.app Path", text: $ghosttyPath)
                    .appHelp("Path to Ghostty.app for external sessions and SFTP.")
            }

            Section("Interface") {
                Toggle("Show Session Sidebar", isOn: $showSidebar)
                    .appHelp("Show or hide the session list in the main window")
            }

            Section("Configuration Files") {
                LabeledContent("App config") {
                    Text(appState.configStore.configTomlURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                TextField("Sessions JSON file", text: $sessionsFile)
                    .appHelp("Relative to the config directory, or an absolute path.")
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
                .appHelp("Control how much detail is written to the log file")
            }

            Section("Sessions") {
                Button("Export Sessions JSON…") { exportSessions() }
                    .appHelp("Save all sessions and folders to a JSON file")
                Button("Import Sessions JSON…") { importSessions() }
                    .appHelp("Replace sessions from a JSON file")
            }

        }
        .padding()
        .frame(width: 520)
        .onAppear {
            ghosttyPath = appState.settings.terminalAppPath
            backend = appState.settings.terminalBackend
            showSidebar = appState.settings.showSidebar
            sessionsFile = appState.settings.sessionsFile
            logLevel = appState.settings.logLevel
        }
        .onDisappear {
            var settings = appState.settings
            settings.terminalAppPath = ghosttyPath
            settings.terminalBackend = backend
            settings.showSidebar = showSidebar
            settings.sessionsFile = sessionsFile
            settings.logLevel = logLevel
            appState.settings = settings
        }
    }

    private func exportSessions() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "sessions.json"
        if panel.runModal() == .OK, let url = panel.url {
            appState.exportSessions(to: url)
        }
    }

    private func importSessions() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.importSessions(from: url)
        }
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
            VStack(spacing: 0) {
                if appState.settings.showCommandBar {
                    ShellCommandBar()
                    Divider()
                }
                TabStripView()
                Divider()
                SplitPaneView()
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
            if appState.offersAutomationSettings {
                Button("Open System Settings") {
                    GhosttyBridge.openAutomationSettings()
                    appState.clearError()
                }
            }
            Button("OK", role: .cancel) {
                appState.clearError()
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}
