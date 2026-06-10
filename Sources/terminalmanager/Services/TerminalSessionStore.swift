import AppKit
import Foundation
import SwiftTerm

@MainActor
final class TerminalSessionStore {
    private var terminals: [UUID: LoggedLocalProcessTerminalView] = [:]

    func terminal(for tabID: UUID, sessionName: String = "") -> LoggedLocalProcessTerminalView {
        if let existing = terminals[tabID] {
            existing.sessionLabel = sessionName
            return existing
        }
        let terminal = LoggedLocalProcessTerminalView(frame: .zero)
        terminal.tabID = tabID
        terminal.sessionLabel = sessionName
        terminal.autoresizingMask = [.width, .height]
        configureAppearance(terminal)
        terminals[tabID] = terminal
        return terminal
    }

    func updateSessionLabel(tabID: UUID, name: String) {
        terminals[tabID]?.sessionLabel = name
    }

    private func configureAppearance(_ terminal: LoggedLocalProcessTerminalView) {
        terminal.font = TerminalFont.preferredMonospaceFont()
        terminal.nativeForegroundColor = .textColor
        terminal.nativeBackgroundColor = .textBackgroundColor
        terminal.optionAsMetaKey = true
        terminal.allowMouseReporting = true
    }

    func isRunning(tabID: UUID) -> Bool {
        terminals[tabID]?.process.running ?? false
    }

    func remove(tabID: UUID) {
        if let terminal = terminals[tabID] {
            terminal.terminate()
            terminal.removeFromSuperview()
        }
        terminals.removeValue(forKey: tabID)
    }
}
