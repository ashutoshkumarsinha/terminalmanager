import AppKit
import Foundation
import SwiftTerm

@MainActor
final class TerminalSessionStore {
    private var terminals: [UUID: LocalProcessTerminalView] = [:]

    func terminal(for tabID: UUID) -> LocalProcessTerminalView {
        if let existing = terminals[tabID] {
            return existing
        }
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.autoresizingMask = [.width, .height]
        configureAppearance(terminal)
        terminals[tabID] = terminal
        return terminal
    }

    private func configureAppearance(_ terminal: LocalProcessTerminalView) {
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
