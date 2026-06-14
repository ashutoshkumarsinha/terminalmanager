import Foundation

/// Export filtered terminal I/O log lines for a tab (EN-02 lite).
enum TerminalIOLogExporter {
    enum ExportError: Error, LocalizedError {
        case loggingDisabled
        case metadataOnly
        case noEntries

        var errorDescription: String? {
            switch self {
            case .loggingDisabled: "Terminal I/O logging is disabled in Settings."
            case .metadataOnly: "Terminal I/O is in metadata-only mode; enable full logging to export text."
            case .noEntries: "No log entries found for this tab."
            }
        }
    }

    static func exportTabLog(
        tabID: UUID,
        sessionName: String,
        to url: URL,
        redactSecrets: Bool = true,
        settings: AppSettings = .defaults
    ) throws {
        guard settings.logTerminalIO else { throw ExportError.loggingDisabled }
        guard !settings.terminalIOMetadataOnly else { throw ExportError.metadataOnly }

        let lines = try collectLines(tabID: tabID, sessionName: sessionName)
        guard !lines.isEmpty else { throw ExportError.noEntries }

        let body = redactSecrets ? redact(lines.joined(separator: "\n")) : lines.joined(separator: "\n")
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    static func collectLines(
        tabID: UUID,
        sessionName: String = "",
        logsDirectory: URL? = nil
    ) throws -> [String] {
        let tabToken = tabID.uuidString
        let logsDir = logsDirectory ?? FileLocations.logsDirectory
        let files = try FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("terminal-io-") && $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var lines: [String] = []
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in content.split(whereSeparator: \.isNewline) {
                let text = String(line)
                guard text.contains("[tab=\(tabToken)]") else { continue }
                lines.append(text)
            }
        }
        return lines
    }

    static func redact(_ text: String) -> String {
        var result = text
        let patterns = [
            #"(?i)(password|passwd|secret|token|apikey|api_key)\s*[=:]\s*\S+"#,
            #"(?i)-----BEGIN [A-Z ]+ PRIVATE KEY-----"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[REDACTED]")
        }
        return result
    }
}
