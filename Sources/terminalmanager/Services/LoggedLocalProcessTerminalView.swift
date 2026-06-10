#if os(macOS)
import AppKit
import SwiftTerm

/// LocalProcessTerminalView that records user input to the terminal I/O log.
final class LoggedLocalProcessTerminalView: LocalProcessTerminalView {
    var tabID: UUID = UUID()
    var sessionLabel: String = ""

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        TerminalIOLogger.shared.logInput(tabID: tabID, session: sessionLabel, data: data)
        super.send(source: source, data: data)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        TerminalIOLogger.shared.logOutput(tabID: tabID, session: sessionLabel, data: slice)
        super.dataReceived(slice: slice)
    }
}
#endif
