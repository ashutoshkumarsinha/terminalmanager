import AppKit
import SwiftUI
import SwiftTerm

struct EmbeddedTerminalView: NSViewRepresentable {
    let tabID: UUID
    let profile: SessionProfile
    let overrideCommand: ConnectionCommand?
    let isActive: Bool
    let terminalStore: TerminalSessionStore
    let onSendInput: ((@escaping (String) -> Void) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(tabID: tabID, terminalStore: terminalStore)
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.coordinator = context.coordinator
        context.coordinator.attach(container: container, profile: profile, overrideCommand: overrideCommand)
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
        coordinator.overrideCommand = overrideCommand
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
    final class Coordinator {
        let tabID: UUID
        let terminalStore: TerminalSessionStore
        weak var container: TerminalContainerView?
        var profile: SessionProfile?
        var overrideCommand: ConnectionCommand?
        var isActive = false
        var onSendInput: ((@escaping (String) -> Void) -> Void)?
        private var didRegisterHandler = false
        private var pendingStart = false

        init(tabID: UUID, terminalStore: TerminalSessionStore) {
            self.tabID = tabID
            self.terminalStore = terminalStore
        }

        func attach(container: TerminalContainerView, profile: SessionProfile, overrideCommand: ConnectionCommand?) {
            self.container = container
            self.profile = profile
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
            terminal.autoresizingMask = [.width, .height]
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
            let command = overrideCommand ?? ConnectionLauncher.command(for: profile)
            terminal.startProcess(
                executable: command.executable,
                args: command.arguments,
                environment: TerminalEnvironment.processEnvironment(overrides: command.environment),
                execName: command.execName,
                currentDirectory: command.workingDirectory
            )
            syncTerminalSize(terminal)

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
            container?.terminal?.removeFromSuperview()
            container?.terminal = nil
            container?.coordinator = nil
            didRegisterHandler = false
            pendingStart = false
        }

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

        private func syncTerminalSize(_ terminal: LocalProcessTerminalView) {
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
    var terminal: LocalProcessTerminalView?
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
                    overrideCommand: tab.overrideCommand,
                    isActive: isActive,
                    terminalStore: appState.terminalStore,
                    onSendInput: { handler in
                        appState.broadcastManager.register(tabID: tab.id, handler: handler)
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
