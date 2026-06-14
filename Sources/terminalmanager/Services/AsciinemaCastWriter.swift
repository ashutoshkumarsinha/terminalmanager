import Foundation

struct AsciinemaCastEvent: Equatable {
    let offset: TimeInterval
    /// `"i"` stdin or `"o"` stdout (asciinema v2).
    let stream: String
    let data: String
}

/// Writes asciinema cast v2 files (https://github.com/asciinema/asciinema/blob/develop/doc/asciicast-v2.md).
enum AsciinemaCastWriter {
    static func encodeData(_ data: ArraySlice<UInt8>) -> String {
        if let text = String(bytes: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(
        to url: URL,
        width: Int,
        height: Int,
        timestamp: Int,
        env: [String: String] = ["TERM": "xterm-256color", "SHELL": "/bin/zsh"],
        title: String? = nil,
        events: [AsciinemaCastEvent]
    ) throws {
        var header: [String: Any] = [
            "version": 2,
            "width": max(1, width),
            "height": max(1, height),
            "timestamp": timestamp,
            "env": env
        ]
        if let title, !title.isEmpty {
            header["title"] = title
        }

        var lines: [String] = []
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        guard let headerLine = String(data: headerData, encoding: .utf8) else {
            throw CastError.encodingFailed
        }
        lines.append(headerLine)

        for event in events {
            let row: [Any] = [event.offset, event.stream, event.data]
            let rowData = try JSONSerialization.data(withJSONObject: row)
            guard let rowLine = String(data: rowData, encoding: .utf8) else {
                throw CastError.encodingFailed
            }
            lines.append(rowLine)
        }

        let body = lines.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    enum CastError: Error {
        case encodingFailed
    }
}

enum SessionRecordingFormat: String, Codable, CaseIterable, Identifiable {
    case plain
    case asciinema

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain: "Plain text"
        case .asciinema: "Asciinema (.cast)"
        }
    }

    var fileExtension: String {
        switch self {
        case .plain: "txt"
        case .asciinema: "cast"
        }
    }
}
