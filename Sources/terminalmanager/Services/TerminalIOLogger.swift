import Foundation

/// Logs terminal input and output to `terminal-io-YYYY-MM-DD.log` in the config logs directory.
final class TerminalIOLogger: @unchecked Sendable {
    static let shared = TerminalIOLogger()

    private let queue = DispatchQueue(label: "com.terminalmanager.terminal-io", qos: .utility)
    private var logFileURL: URL?
    private var fileHandle: FileHandle?
    private var outputBuffer = ""
    private var flushWorkItem: DispatchWorkItem?

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private init() {}

    func logInput(tabID: UUID, session: String, data: ArraySlice<UInt8>) {
        guard let text = decode(data), !text.isEmpty else { return }
        let entry = formatEntry(direction: "INPUT", tabID: tabID, session: session, text: text)
        queue.async { [weak self] in
            self?.writeImmediately(entry)
        }
    }

    func logOutput(tabID: UUID, session: String, data: ArraySlice<UInt8>) {
        guard let text = decode(data), !text.isEmpty else { return }
        let entry = formatEntry(direction: "OUTPUT", tabID: tabID, session: session, text: text)
        queue.async { [weak self] in
            self?.bufferOutput(entry)
        }
    }

    private func formatEntry(direction: String, tabID: UUID, session: String, text: String) -> String {
        let timestamp = timestampFormatter.string(from: Date())
        let label = session.isEmpty ? "session" : session
        let sanitized = sanitizeForLog(text)
        return "[\(timestamp)] [\(direction)] [tab=\(tabID.uuidString)] [\(label)] \(sanitized)"
    }

    private func decode(_ data: ArraySlice<UInt8>) -> String? {
        String(bytes: data, encoding: .utf8)
    }

    private func sanitizeForLog(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func bufferOutput(_ entry: String) {
        if outputBuffer.isEmpty {
            outputBuffer = entry
        } else {
            outputBuffer += "\n" + entry
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushOutputBuffer()
        }
        flushWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    private func flushOutputBuffer() {
        guard !outputBuffer.isEmpty else { return }
        writeImmediately(outputBuffer)
        outputBuffer = ""
    }

    private func writeImmediately(_ text: String) {
        guard let handle = openLogHandle() else { return }
        guard let data = (text + "\n").data(using: .utf8) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
    }

    private func openLogHandle() -> FileHandle? {
        let logsDir = FileLocations.logsDirectory
        let day = fileNameFormatter.string(from: Date())
        let url = logsDir.appendingPathComponent("terminal-io-\(day).log")

        if logFileURL != url {
            try? fileHandle?.close()
            fileHandle = nil
            logFileURL = url
        }

        if let fileHandle {
            return fileHandle
        }

        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            fileHandle = handle
            return handle
        } catch {
            return nil
        }
    }
}
