import Foundation
import SwiftTerm

enum TranscriptExporter {
    static func exportScrollback(from terminal: LoggedLocalProcessTerminalView, to url: URL) throws {
        let data = terminal.getTerminal().getBufferAsData()
        try data.write(to: url, options: .atomic)
    }

    static func exportSelection(from terminal: LoggedLocalProcessTerminalView, to url: URL) throws {
        guard let text = terminal.getSelection(), !text.isEmpty else {
            throw ExportError.noSelection
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    enum ExportError: Error, LocalizedError {
        case noSelection

        var errorDescription: String? {
            switch self {
            case .noSelection: "No text is selected in the terminal."
            }
        }
    }
}
