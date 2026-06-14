import Foundation
import SwiftTerm

struct ANSIPalette: Codable, Equatable, Hashable {
    var black: String
    var red: String
    var green: String
    var yellow: String
    var blue: String
    var magenta: String
    var cyan: String
    var white: String

    static let `default` = ANSIPalette(
        black: "#000000",
        red: "#CC0000",
        green: "#009900",
        yellow: "#999900",
        blue: "#0000CC",
        magenta: "#990099",
        cyan: "#009999",
        white: "#CCCCCC"
    )
}

enum ANSIPaletteCodec {
    static func apply(_ palette: ANSIPalette?, to terminal: LoggedLocalProcessTerminalView) {
        guard let palette else { return }
        let base = [
            palette.black, palette.red, palette.green, palette.yellow,
            palette.blue, palette.magenta, palette.cyan, palette.white
        ]
        var colors: [Color] = []
        for hex in base {
            guard let color = color(from: hex) else { return }
            colors.append(color)
        }
        for hex in base {
            guard let color = color(from: hex, brighten: 0.35) else { return }
            colors.append(color)
        }
        guard colors.count == 16 else { return }
        terminal.installColors(colors)
    }

    /// Exposed for tests and smoke checks.
    static func parseColor(from hex: String, brighten: CGFloat = 0) -> Color? {
        color(from: hex, brighten: brighten)
    }

    private static func color(from hex: String, brighten: CGFloat = 0) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        var r = CGFloat((value >> 16) & 0xFF) / 255
        var g = CGFloat((value >> 8) & 0xFF) / 255
        var b = CGFloat(value & 0xFF) / 255
        if brighten > 0 {
            r = min(1, r + brighten)
            g = min(1, g + brighten)
            b = min(1, b + brighten)
        }
        return Color(
            red: UInt16(r * 65535),
            green: UInt16(g * 65535),
            blue: UInt16(b * 65535)
        )
    }
}

#if os(macOS)
import AppKit
#endif
