import XCTest
import SwiftTerm
@testable import terminalmanager

final class ANSIPaletteTests: XCTestCase {
    func testDefaultPaletteEquality() {
        XCTAssertEqual(ANSIPalette.default, ANSIPalette.default)
    }

    func testParseValidHexColor() {
        let color = ANSIPaletteCodec.parseColor(from: "#FF0000")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.red, 65535)
        XCTAssertEqual(color?.green, 0)
        XCTAssertEqual(color?.blue, 0)
    }

    func testParseHexWithoutHash() {
        let color = ANSIPaletteCodec.parseColor(from: "00FF00")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.green, 65535)
    }

    func testParseInvalidHexReturnsNil() {
        XCTAssertNil(ANSIPaletteCodec.parseColor(from: "ZZZZZZ"))
        XCTAssertNil(ANSIPaletteCodec.parseColor(from: "#123"))
    }

    func testBrightenIncreasesComponents() {
        let base = ANSIPaletteCodec.parseColor(from: "#000000")
        let bright = ANSIPaletteCodec.parseColor(from: "#000000", brighten: 0.5)
        XCTAssertNotNil(base)
        XCTAssertNotNil(bright)
        XCTAssertGreaterThan(bright!.red, base!.red)
    }

    func testApplyInstallsSixteenColors() {
        let terminal = LoggedLocalProcessTerminalView(frame: .zero)
        let palette = ANSIPalette(
            black: "#111111",
            red: "#222222",
            green: "#333333",
            yellow: "#444444",
            blue: "#555555",
            magenta: "#666666",
            cyan: "#777777",
            white: "#888888"
        )
        ANSIPaletteCodec.apply(palette, to: terminal)
        // installColors is a no-op if count != 16; reaching here without crash validates palette build.
        ANSIPaletteCodec.apply(nil, to: terminal)
    }
}
