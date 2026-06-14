import Foundation

/// Logs terminal input and output to `terminal-io-YYYY-MM-DD.log` in the config logs directory.
final class TerminalIOLogger: @unchecked Sendable {
    static let shared = TerminalIOLogger()

    private let queue = DispatchQueue(label: "com.terminalmanager.terminal-io", qos: .utility)
    private var logFileURL: URL?
    private var fileHandle: FileHandle?
    private var outputBuffer = ""
    private var flushWorkItem: DispatchWorkItem?
    private var loggingEnabled = AppSettings.defaults.logTerminalIO
    private var maxLogBytes = AppSettings.defaults.terminalIOMaxMB * 1_024 * 1_024
    private var metadataOnly = AppSettings.defaults.terminalIOMetadataOnly

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

    func configure(enabled: Bool, maxMB: Int, metadataOnly: Bool = false) {
        queue.async { [weak self] in
            self?.loggingEnabled = enabled
            self?.maxLogBytes = max(1, maxMB) * 1_024 * 1_024
            self?.metadataOnly = metadataOnly
        }
    }

    func logInput(tabID: UUID, session: String, data: ArraySlice<UInt8>) {
        guard loggingEnabled, !data.isEmpty else { return }
        let entry = makeEntry(direction: "INPUT", tabID: tabID, session: session, data: data)
        queue.async { [weak self] in
            self?.writeImmediately(entry)
        }
    }

    func logOutput(tabID: UUID, session: String, data: ArraySlice<UInt8>) {
        guard loggingEnabled, !data.isEmpty else { return }
        let entry = makeEntry(direction: "OUTPUT", tabID: tabID, session: session, data: data)
        queue.async { [weak self] in
            self?.bufferOutput(entry)
        }
    }

    static func metadataEntry(
        direction: String,
        tabID: UUID,
        session: String,
        byteCount: Int,
        timestamp: Date = Date(),
        timestampFormatter: DateFormatter? = nil
    ) -> String {
        let formatter = timestampFormatter ?? {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()
        let label = session.isEmpty ? "session" : session
        return "[\(formatter.string(from: timestamp))] [\(direction)] [tab=\(tabID.uuidString)] [\(label)] \(byteCount) bytes"
    }

    private func makeEntry(direction: String, tabID: UUID, session: String, data: ArraySlice<UInt8>) -> String {
        if metadataOnly {
            return Self.metadataEntry(
                direction: direction,
                tabID: tabID,
                session: session,
                byteCount: data.count,
                timestamp: Date(),
                timestampFormatter: timestampFormatter
            )
        }
        guard let text = decode(data), !text.isEmpty else { return "" }
        return formatEntry(direction: direction, tabID: tabID, session: session, text: text)
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
        guard !entry.isEmpty else { return }
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
        guard loggingEnabled, !text.isEmpty, let handle = openLogHandle() else { return }
        rotateIfNeeded(for: handle)
        guard let data = (text + "\n").data(using: .utf8) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
    }

    private func rotateIfNeeded(for handle: FileHandle) {
        guard let url = logFileURL else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size >= maxLogBytes else { return }

        try? handle.close()
        fileHandle = nil

        let rotated = url.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
        FileManager.default.createFile(atPath: url.path, contents: nil)
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
