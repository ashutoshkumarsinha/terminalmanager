#if os(macOS)
import AppKit
import SwiftTerm

/// LocalProcessTerminalView that records user input to the terminal I/O log.
final class LoggedLocalProcessTerminalView: LocalProcessTerminalView {
    var tabID: UUID = UUID()
    var sessionLabel: String = ""
    var onProcessTerminated: ((Int32?) -> Void)?
    var onOutputReceived: ((UUID) -> Void)?
    var copyOnSelect = false
    var pasteOnMiddleClick = true

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        TerminalIOLogger.shared.logInput(tabID: tabID, session: sessionLabel, data: data)
        SessionRecorder.shared.append(tabID: tabID, direction: "INPUT", data: data)
        super.send(source: source, data: data)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        TerminalIOLogger.shared.logOutput(tabID: tabID, session: sessionLabel, data: slice)
        SessionRecorder.shared.append(tabID: tabID, direction: "OUTPUT", data: slice)
        onOutputReceived?(tabID)
        super.dataReceived(slice: slice)
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        SessionRecorder.shared.stop(tabID: tabID)
        onProcessTerminated?(exitCode)
        super.processTerminated(source, exitCode: exitCode)
    }

    override func selectionChanged(source: Terminal) {
        super.selectionChanged(source: source)
        guard copyOnSelect, let text = getSelection(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard pasteOnMiddleClick, event.buttonNumber == 2,
              let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            super.otherMouseDown(with: event)
            return
        }
        guard let data = text.data(using: .utf8) else {
            super.otherMouseDown(with: event)
            return
        }
        send(source: self, data: ArraySlice(data))
    }
}
#endif
