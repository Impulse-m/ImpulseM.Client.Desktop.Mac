import AppKit
import XCTest
@testable import ColorPalette

final class ImpulsePaletteTests: XCTestCase {
    func testDayClassicPrimaryAccentIsImpulseBlue() {
        XCTAssertEqual(rgbValue(dayClassicPalette.accentList[0].accent), 0x2085DF)
    }

    func testNightAccentBackgroundIsImpulseSurface() {
        XCTAssertEqual(rgbValue(nightAccentPalette.background), 0x1D2128)
    }

    func testNightAccentChatBackgroundIsImpulseSurface() {
        XCTAssertEqual(rgbValue(nightAccentPalette.chatBackground), 0x1D2128)
    }

    func testNightAccentListBackgroundIsImpulseSurface() {
        XCTAssertEqual(rgbValue(nightAccentPalette.listBackground), 0x14181F)
    }

    private func rgbValue(_ color: NSColor) -> UInt32 {
        guard let converted: NSColor = color.usingColorSpace(NSColorSpace.deviceRGB) else {
            return 0
        }
        let red: UInt32 = UInt32((converted.redComponent * 255).rounded())
        let green: UInt32 = UInt32((converted.greenComponent * 255).rounded())
        let blue: UInt32 = UInt32((converted.blueComponent * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }
}
