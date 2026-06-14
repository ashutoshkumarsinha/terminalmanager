import AppKit
import Foundation
import SwiftTerm

@MainActor
final class TerminalSessionStore {
    private var terminals: [UUID: LoggedLocalProcessTerminalView] = [:]
    private var appearanceSettings: AppSettings = .defaults

    func configureAppearance(from settings: AppSettings) {
        appearanceSettings = settings
        for terminal in terminals.values {
            applyAppearance(terminal, settings: settings)
        }
    }

    func terminal(for tabID: UUID, sessionName: String = "") -> LoggedLocalProcessTerminalView {
        if let existing = terminals[tabID] {
            existing.sessionLabel = sessionName
            return existing
        }
        let terminal = LoggedLocalProcessTerminalView(frame: .zero)
        terminal.tabID = tabID
        terminal.sessionLabel = sessionName
        terminal.autoresizingMask = [.width, .height]
        applyAppearance(terminal, settings: appearanceSettings)
        terminals[tabID] = terminal
        return terminal
    }

    func updateSessionLabel(tabID: UUID, name: String) {
        terminals[tabID]?.sessionLabel = name
    }

    private func applyAppearance(_ terminal: LoggedLocalProcessTerminalView, settings: AppSettings) {
        if let font = NSFont(name: settings.terminalFontName, size: settings.terminalFontSize) {
            terminal.font = font
        } else {
            terminal.font = TerminalFont.preferredMonospaceFont(size: settings.terminalFontSize)
        }

        switch settings.terminalTheme {
        case .system:
            terminal.nativeForegroundColor = .textColor
            terminal.nativeBackgroundColor = .textBackgroundColor
        case .light:
            terminal.nativeForegroundColor = .black
            terminal.nativeBackgroundColor = .white
        case .dark:
            terminal.nativeForegroundColor = .white
            terminal.nativeBackgroundColor = .black
        }

        terminal.optionAsMetaKey = true
        terminal.allowMouseReporting = true
        terminal.copyOnSelect = settings.copyOnSelect
        terminal.pasteOnMiddleClick = settings.pasteOnMiddleClick
        ANSIPaletteCodec.apply(settings.ansiPalette, to: terminal)
        applyScrollbackLimit(terminal, settings: settings)
    }

    private func applyScrollbackLimit(_ terminal: LoggedLocalProcessTerminalView, settings: AppSettings) {
        let lines = max(0, settings.maxScrollbackLines)
        terminal.changeScrollback(lines > 0 ? lines : nil)
    }

    func isRunning(tabID: UUID) -> Bool {
        terminals[tabID]?.process.running ?? false
    }

    @discardableResult
    func findNext(tabID: UUID, query: String, searchFromEnd: Bool = false) -> Bool {
        terminals[tabID]?.findNextOccurrence(query, searchFromEnd: searchFromEnd) ?? false
    }

    @discardableResult
    func findPrevious(tabID: UUID, query: String) -> Bool {
        terminals[tabID]?.findPreviousOccurrence(query) ?? false
    }

    func remove(tabID: UUID) {
        if let terminal = terminals[tabID] {
            terminal.terminate()
            terminal.removeFromSuperview()
        }
        terminals.removeValue(forKey: tabID)
    }

    /// Terminates the PTY and drops the terminal view to free scrollback (PF-10).
    func hibernate(tabID: UUID) {
        remove(tabID: tabID)
    }

    func hasTerminal(tabID: UUID) -> Bool {
        terminals[tabID] != nil
    }

    func exportScrollback(tabID: UUID, to url: URL) throws {
        guard let terminal = terminals[tabID] else {
            throw TranscriptExporter.ExportError.noSelection
        }
        try TranscriptExporter.exportScrollback(from: terminal, to: url)
    }

    func exportSelection(tabID: UUID, to url: URL) throws {
        guard let terminal = terminals[tabID] else {
            throw TranscriptExporter.ExportError.noSelection
        }
        try TranscriptExporter.exportSelection(from: terminal, to: url)
    }
}
