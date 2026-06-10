import AppKit
import SwiftUI
import SwiftTerm

struct EmbeddedTerminalView: NSViewRepresentable {
    let tabID: UUID
    let profile: SessionProfile
    let isActive: Bool
    let terminalStore: TerminalSessionStore
    let onSendInput: ((@escaping (String) -> Void) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(tabID: tabID, terminalStore: terminalStore)
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.coordinator = context.coordinator
        context.coordinator.attach(container: container, profile: profile)
        context.coordinator.isActive = isActive
        context.coordinator.onSendInput = onSendInput
        context.coordinator.reattachIfNeeded()
        return container
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        context.coordinator.profile = profile
        context.coordinator.isActive = isActive
        context.coordinator.onSendInput = onSendInput
        context.coordinator.registerBroadcastHandlerIfNeeded()
        context.coordinator.reattachIfNeeded()
        context.coordinator.startIfNeeded()
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
        var isActive = false
        var onSendInput: ((@escaping (String) -> Void) -> Void)?
        private var didRegisterHandler = false
        private var pendingStart = false

        init(tabID: UUID, terminalStore: TerminalSessionStore) {
            self.tabID = tabID
            self.terminalStore = terminalStore
        }

        func attach(container: TerminalContainerView, profile: SessionProfile) {
            self.container = container
            self.profile = profile
        }

        func registerBroadcastHandlerIfNeeded() {
            guard !didRegisterHandler else { return }
            didRegisterHandler = true
            onSendInput? { [weak self] text in
                self?.send(text)
            }
        }

        func reattachIfNeeded() {
            guard let container else { return }
            let terminal = terminalStore.terminal(for: tabID)
            if container.terminal !== terminal {
                container.terminal?.removeFromSuperview()
                container.terminal = terminal
                container.addSubview(terminal)
            }
            terminal.autoresizingMask = [.width, .height]
            terminal.frame = container.bounds
            if terminalStore.isRunning(tabID: tabID) {
                terminal.setNeedsDisplay(terminal.bounds)
                terminal.layoutSubtreeIfNeeded()
            }
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
            let command = ConnectionLauncher.command(for: profile)
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
            terminal.process.send(data: ArraySlice(data))
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            coordinator?.reattachIfNeeded()
            coordinator?.startIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        if let terminal {
            terminal.frame = bounds
            if bounds.width > 10, bounds.height > 10 {
                terminal.setNeedsDisplay(bounds)
                if terminal.process.running {
                    terminal.sizeChanged(
                        source: terminal,
                        newCols: terminal.getTerminal().cols,
                        newRows: terminal.getTerminal().rows
                    )
                }
            }
        }
        coordinator?.startIfNeeded()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        coordinator?.reattachIfNeeded()
    }
}

struct TerminalHostView: View {
    let tab: TerminalTab
    var isActive: Bool = true
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if tab.backend == .ghostty {
                ExternalTerminalPlaceholderView(tab: tab)
            } else if let profile = tab.profile {
                EmbeddedTerminalView(
                    tabID: tab.id,
                    profile: profile,
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

struct ExternalTerminalPlaceholderView: View {
    let tab: TerminalTab

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Running in Ghostty")
                .font(.title2)
            if let profile = tab.profile {
                Text(profile.name)
                    .foregroundStyle(.secondary)
                Text(ConnectionLauncher.command(for: profile).displayCommand)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Switch to embedded mode in Settings to render sessions inside Terminal Manager.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
