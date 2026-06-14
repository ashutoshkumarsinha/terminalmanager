import AppKit
import SwiftUI
import SwiftTerm

struct EmbeddedTerminalView: NSViewRepresentable {
    let tabID: UUID
    let profile: SessionProfile
    let tab: TerminalTab
    let overrideCommand: ConnectionCommand?
    let isActive: Bool
    let bastionProfiles: [BastionProfile]
    let copyOnSelect: Bool
    let pasteOnMiddleClick: Bool
    let ansiPalette: ANSIPalette?
    let terminalStore: TerminalSessionStore
    let onSendInput: ((@escaping (String) -> Void) -> Void)?
    let onSessionStateChange: ((TabSessionState, Int32?) -> Void)?
    let onOutputReceived: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            tabID: tabID,
            terminalStore: terminalStore,
            onSessionStateChange: onSessionStateChange
        )
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.coordinator = context.coordinator
        context.coordinator.attach(container: container, profile: profile, tab: tab, overrideCommand: overrideCommand)
        context.coordinator.bastionProfiles = bastionProfiles
        context.coordinator.copyOnSelect = copyOnSelect
        context.coordinator.pasteOnMiddleClick = pasteOnMiddleClick
        context.coordinator.ansiPalette = ansiPalette
        context.coordinator.onOutputReceived = onOutputReceived
        context.coordinator.isActive = isActive
        context.coordinator.onSendInput = onSendInput
        context.coordinator.reattachIfNeeded()
        return container
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        let coordinator = context.coordinator
        let wasActive = coordinator.isActive
        let profileChanged = coordinator.profile?.id != profile.id

        coordinator.profile = profile
        coordinator.tab = tab
        coordinator.overrideCommand = overrideCommand
        coordinator.bastionProfiles = bastionProfiles
        coordinator.copyOnSelect = copyOnSelect
        coordinator.pasteOnMiddleClick = pasteOnMiddleClick
        coordinator.ansiPalette = ansiPalette
        coordinator.onOutputReceived = onOutputReceived
        coordinator.isActive = isActive
        coordinator.onSendInput = onSendInput
        terminalStore.updateSessionLabel(tabID: tabID, name: profile.name)
        coordinator.registerBroadcastHandlerIfNeeded()

        if profileChanged || wasActive != isActive {
            coordinator.reattachIfNeeded()
            coordinator.startIfNeeded()
        }
    }

    static func dismantleNSView(_ container: TerminalContainerView, coordinator: Coordinator) {
        coordinator.detachFromContainer()
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let tabID: UUID
        let terminalStore: TerminalSessionStore
        let onSessionStateChange: ((TabSessionState, Int32?) -> Void)?
        weak var container: TerminalContainerView?
        var profile: SessionProfile?
        var tab: TerminalTab?
        var overrideCommand: ConnectionCommand?
        var bastionProfiles: [BastionProfile] = []
        var copyOnSelect = false
        var pasteOnMiddleClick = true
        var ansiPalette: ANSIPalette?
        var isActive = false
        var onSendInput: ((@escaping (String) -> Void) -> Void)?
        var onOutputReceived: (() -> Void)?
        private var didRegisterHandler = false
        private var pendingStart = false

        init(
            tabID: UUID,
            terminalStore: TerminalSessionStore,
            onSessionStateChange: ((TabSessionState, Int32?) -> Void)?
        ) {
            self.tabID = tabID
            self.terminalStore = terminalStore
            self.onSessionStateChange = onSessionStateChange
        }

        func attach(container: TerminalContainerView, profile: SessionProfile, tab: TerminalTab, overrideCommand: ConnectionCommand?) {
            self.container = container
            self.profile = profile
            self.tab = tab
            self.overrideCommand = overrideCommand
            terminalStore.updateSessionLabel(tabID: tabID, name: profile.name)
        }

        func registerBroadcastHandlerIfNeeded() {
            guard !didRegisterHandler else { return }
            didRegisterHandler = true
            onSendInput? { [weak self] text in
                self?.send(text)
            }
        }

        func reattachIfNeeded() {
            guard let container, let profile else { return }
            let terminal = terminalStore.terminal(for: tabID, sessionName: profile.name)
            if container.terminal !== terminal {
                container.terminal?.removeFromSuperview()
                container.terminal = terminal
                container.addSubview(terminal)
            }
            terminal.processDelegate = self
            terminal.copyOnSelect = copyOnSelect
            terminal.pasteOnMiddleClick = pasteOnMiddleClick
            ANSIPaletteCodec.apply(ansiPalette, to: terminal)
            terminal.onOutputReceived = { [weak self] _ in
                self?.onOutputReceived?()
            }
            terminal.onProcessTerminated = { [weak self] exitCode in
                self?.onSessionStateChange?(.exited, exitCode)
            }
            terminal.frame = container.bounds
        }

        func startIfNeeded() {
            guard isActive, let container, let profile else { return }
            guard container.bounds.width > 10, container.bounds.height > 10 else {
                scheduleRetry()
                return
            }

            reattachIfNeeded()
            guard let terminal = container.terminal, !terminalStore.isRunning(tabID: tabID) else { return }

            terminal.layoutSubtreeIfNeeded()
            let tabOverrides = tab.map {
                (
                    remoteEnvironment: $0.remoteEnvironmentOverride,
                    remoteWorkingDirectory: $0.remoteWorkingDirectoryOverride
                )
            }
            let command = overrideCommand ?? ConnectionLauncher.command(
                for: profile,
                bastions: bastionProfiles,
                tabOverrides: tabOverrides
            )
            terminal.startProcess(
                executable: command.executable,
                args: command.arguments,
                environment: TerminalEnvironment.processEnvironment(overrides: command.environment),
                execName: command.execName,
                currentDirectory: command.workingDirectory
            )
            syncTerminalSize(terminal)
            onSessionStateChange?(.running, nil)

            let lines = command.startupCommands
            guard !lines.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + command.startupDelay) { [weak self] in
                guard let self else { return }
                for line in lines {
                    self.send(line + "\n")
                }
            }
        }

        func detachFromContainer() {
            container?.terminal?.processDelegate = nil
            container?.terminal?.onProcessTerminated = nil
            container?.terminal?.removeFromSuperview()
            container?.terminal = nil
            container?.coordinator = nil
            didRegisterHandler = false
            pendingStart = false
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {}

        private func scheduleRetry() {
            guard !pendingStart else { return }
            pendingStart = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingStart = false
                self.startIfNeeded()
            }
        }

        private func send(_ text: String) {
            guard let terminal = container?.terminal, let data = text.data(using: .utf8) else { return }
            let slice = ArraySlice(data)
            TerminalIOLogger.shared.logInput(tabID: tabID, session: profile?.name ?? "", data: slice)
            terminal.process.send(data: slice)
        }

        private func syncTerminalSize(_ terminal: LoggedLocalProcessTerminalView) {
            DispatchQueue.main.async {
                guard terminal.process.running else { return }
                terminal.sizeChanged(
                    source: terminal,
                    newCols: terminal.getTerminal().cols,
                    newRows: terminal.getTerminal().rows
                )
            }
        }
    }
}

final class TerminalContainerView: NSView {
    weak var coordinator: EmbeddedTerminalView.Coordinator?
    var terminal: LoggedLocalProcessTerminalView?
    private var lastReportedCols = 0
    private var lastReportedRows = 0
    private var resizeWorkItem: DispatchWorkItem?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            coordinator?.reattachIfNeeded()
            coordinator?.startIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        guard let terminal else { return }
        terminal.frame = bounds
        guard bounds.width > 10, bounds.height > 10, terminal.process.running else { return }

        let cols = Int(terminal.getTerminal().cols)
        let rows = Int(terminal.getTerminal().rows)
        guard cols != lastReportedCols || rows != lastReportedRows else { return }

        resizeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self, weak terminal] in
            guard let self, let terminal, terminal.process.running else { return }
            let cols = Int(terminal.getTerminal().cols)
            let rows = Int(terminal.getTerminal().rows)
            guard cols != self.lastReportedCols || rows != self.lastReportedRows else { return }
            self.lastReportedCols = cols
            self.lastReportedRows = rows
            if let tabID = self.coordinator?.tabID {
                SessionRecorder.shared.updateTerminalSize(tabID: tabID, cols: cols, rows: rows)
            }
            terminal.sizeChanged(source: terminal, newCols: cols, newRows: rows)
        }
        resizeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        if oldSize != bounds.size {
            coordinator?.reattachIfNeeded()
        }
    }
}

struct TerminalHostView: View {
    let tab: TerminalTab
    var isActive: Bool = true
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let profile = tab.profile {
                EmbeddedTerminalView(
                    tabID: tab.id,
                    profile: profile,
                    tab: tab,
                    overrideCommand: tab.overrideCommand,
                    isActive: isActive,
                    bastionProfiles: appState.settings.bastionProfiles,
                    copyOnSelect: appState.settings.copyOnSelect,
                    pasteOnMiddleClick: appState.settings.pasteOnMiddleClick,
                    ansiPalette: appState.settings.ansiPalette,
                    terminalStore: appState.terminalStore,
                    onSendInput: { handler in
                        appState.broadcastManager.register(tabID: tab.id, handler: handler)
                    },
                    onSessionStateChange: { state, exitCode in
                        appState.updateTabSessionState(tabID: tab.id, state: state, exitCode: exitCode)
                    },
                    onOutputReceived: {
                        appState.recordTerminalOutput(tabID: tab.id)
                    }
                )
            } else {
                ContentUnavailableView("No Session", systemImage: "terminal")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
