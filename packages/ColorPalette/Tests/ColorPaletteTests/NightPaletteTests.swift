import AppKit
import XCTest
@testable import ColorPalette

final class NightPaletteTests: XCTestCase {
    func testNightAccentAccentListFirstIsPrimaryNight() {
        XCTAssertEqual(rgbValue(nightAccentPalette.accentList[0].accent), 0x58AEEE)
        XCTAssertEqual(rgbValue(nightAccentPalette.basicAccent), 0x58AEEE)
        XCTAssertEqual(rgbValue(nightAccentPalette.accent), 0x58AEEE)
        XCTAssertEqual(rgbValue(nightAccentPalette.accentIcon), 0x58AEEE)
    }

    func testNightAccentLinkUsesLightPrimaryNight() {
        XCTAssertEqual(rgbValue(nightAccentPalette.link), 0x7CBDE8)
        XCTAssertEqual(rgbValue(nightAccentPalette.linkBubble_incoming), 0x7CBDE8)
    }

    func testNightAccentSurfacesUseNightTokens() {
        XCTAssertEqual(rgbValue(nightAccentPalette.background), 0x1D2128)
        XCTAssertEqual(rgbValue(nightAccentPalette.chatBackground), 0x1D2128)
        XCTAssertEqual(rgbValue(nightAccentPalette.listBackground), 0x14181F)
    }

    func testNightAccentShadesFollowRecolorMapping() {
        XCTAssertEqual(rgbValue(nightAccentPalette.accentSelect), 0x4E709A)
        XCTAssertEqual(rgbValue(nightAccentPalette.selectText), 0x4F7298)
        XCTAssertEqual(rgbValue(nightAccentPalette.revealAction_neutral1_background), 0x2E87C8)
    }

    func testNightAccentBorderIsTintedDivider() {
        XCTAssertEqual(rgbValue(nightAccentPalette.border), 0x101824)
        XCTAssertEqual(rgbValue(nightAccentPalette.grayBackground), 0x101824)
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
