import Foundation

struct ParsedConnectionURI: Equatable {
    var protocolType: ConnectionProtocol
    var host: String
    var port: Int?
    var username: String
}

enum ConnectionURIParser {
    static func looksLikeURI(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).contains("://")
    }

    static func parse(_ input: String) -> ParsedConnectionURI? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("%20"), trimmed.contains("://") {
            if let decoded = trimmed.removingPercentEncoding {
                trimmed = decoded
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if trimmed.contains(" ") {
                return parsePuttyStyleCommandLine(trimmed)
            }
        }

        if trimmed.contains("://") {
            return parseSchemeURI(trimmed)
        }

        return nil
    }

    private static func parseSchemeURI(_ input: String) -> ParsedConnectionURI? {
        let normalized = input.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let components = URLComponents(string: normalized),
           let scheme = components.scheme,
           let protocolType = protocolType(forScheme: scheme) {
            let host = components.host ?? ""
            if !host.isEmpty {
                return ParsedConnectionURI(
                    protocolType: protocolType,
                    host: host,
                    port: components.port ?? protocolType.defaultPort,
                    username: components.user ?? ""
                )
            }
        }
        return parseManualSchemeURI(normalized)
    }

    /// Fallback parser compatible with SuperPuTTY-style `ssh2://host:port` strings.
    private static func parseManualSchemeURI(_ input: String) -> ParsedConnectionURI? {
        guard let range = input.range(of: "://") else { return nil }
        let scheme = String(input[..<range.lowerBound])
        guard let protocolType = protocolType(forScheme: scheme) else { return nil }

        var remainder = String(input[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var username = ""
        if let atIndex = remainder.lastIndex(of: "@") {
            username = String(remainder[..<atIndex])
            remainder = String(remainder[remainder.index(after: atIndex)...])
        }

        var host = remainder
        var port = protocolType.defaultPort
        if let colonIndex = remainder.lastIndex(of: ":"),
           Int(remainder[remainder.index(after: colonIndex)...]) != nil {
            let portPart = String(remainder[remainder.index(after: colonIndex)...])
            if let parsedPort = Int(portPart) {
                port = parsedPort
                host = String(remainder[..<colonIndex])
            }
        }

        guard !host.isEmpty else { return nil }
        return ParsedConnectionURI(
            protocolType: protocolType,
            host: host,
            port: port,
            username: username
        )
    }

    private static func parsePuttyStyleCommandLine(_ cmdLine: String) -> ParsedConnectionURI? {
        var tokens = cmdLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var result: ParsedConnectionURI
        if tokens[0].contains("://"), let parsed = parseSchemeURI(tokens[0]) {
            result = parsed
            tokens.removeFirst()
        } else {
            result = ParsedConnectionURI(protocolType: .ssh, host: tokens[0], port: 22, username: "")
            tokens.removeFirst()
        }

        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case "-P":
                index += 1
                if index < tokens.count {
                    result.port = Int(tokens[index])
                }
            case "-l":
                index += 1
                if index < tokens.count {
                    result.username = tokens[index]
                }
            case "-ssh", "-ssh2":
                result.protocolType = .ssh
            case "-telnet":
                result.protocolType = .telnet
            case "-rlogin":
                result.protocolType = .rlogin
            case "-raw":
                result.protocolType = .raw
            case "-pw":
                index += 1
            default:
                if result.host.isEmpty {
                    result.host = tokens[index]
                }
            }
            index += 1
        }

        return result.host.isEmpty ? nil : result
    }

    private static func protocolType(forScheme scheme: String) -> ConnectionProtocol? {
        switch scheme.lowercased() {
        case "ssh", "ssh2":
            return .ssh
        case "telnet":
            return .telnet
        case "rlogin":
            return .rlogin
        case "raw", "tcp":
            return .raw
        default:
            return nil
        }
    }
}

extension SessionProfile {
    mutating func apply(parsedURI: ParsedConnectionURI) {
        host = parsedURI.host
        username = parsedURI.username
        protocolType = parsedURI.protocolType
        port = parsedURI.port ?? parsedURI.protocolType.defaultPort
    }

    static func quickConnect(from connectionString: String) -> SessionProfile? {
        guard let parsed = ConnectionURIParser.parse(connectionString),
              !parsed.host.isEmpty else {
            return nil
        }
        return SessionProfile(
            name: parsed.host,
            host: parsed.host,
            port: parsed.port,
            username: parsed.username,
            protocolType: parsed.protocolType
        )
    }
}
