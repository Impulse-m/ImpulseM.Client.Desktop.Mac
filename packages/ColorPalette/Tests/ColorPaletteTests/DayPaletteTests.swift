import AppKit
import XCTest
@testable import ColorPalette

final class DayPaletteTests: XCTestCase {
    func testWhitePaletteAccentListFirstIsPrimaryDay() {
        XCTAssertEqual(rgbValue(whitePalette.accentList[0].accent), 0x2085DF)
        XCTAssertEqual(rgbValue(whitePalette.basicAccent), 0x2085DF)
        XCTAssertEqual(rgbValue(whitePalette.accent), 0x2085DF)
        XCTAssertEqual(rgbValue(whitePalette.accentIcon), 0x2085DF)
    }

    func testWhitePaletteLinkUsesLinkDay() {
        XCTAssertEqual(rgbValue(whitePalette.link), 0x106ACC)
        XCTAssertEqual(rgbValue(whitePalette.linkBubble_incoming), 0x106ACC)
    }

    func testWhitePaletteShadesFollowRecolorMapping() {
        XCTAssertEqual(rgbValue(whitePalette.accentSelect), 0x4E99DA)
        XCTAssertEqual(rgbValue(whitePalette.fileActivityForegroundBubble_outgoing), 0x4E99DA)
        XCTAssertEqual(rgbValue(whitePalette.badge), 0x4BABF7)
        XCTAssertEqual(rgbValue(whitePalette.fileActivityBackground), 0x4BABF7)
        XCTAssertEqual(rgbValue(whitePalette.waveformForeground), 0x4BABF7)
        XCTAssertEqual(rgbValue(whitePalette.revealAction_neutral1_background), 0x4591FF)
        XCTAssertEqual(rgbValue(whitePalette.focusAnimationColor), 0x6CB2F7)
    }

    func testDayClassicAccentListFirstIsPrimaryDay() {
        XCTAssertEqual(rgbValue(dayClassicPalette.accentList[0].accent), 0x2085DF)
        XCTAssertEqual(rgbValue(dayClassicPalette.basicAccent), 0x2085DF)
        XCTAssertEqual(rgbValue(dayClassicPalette.accent), 0x2085DF)
        XCTAssertEqual(rgbValue(dayClassicPalette.accentIcon), 0x2085DF)
    }

    func testDayClassicLinkUsesLinkDay() {
        XCTAssertEqual(rgbValue(dayClassicPalette.link), 0x106ACC)
        XCTAssertEqual(rgbValue(dayClassicPalette.linkBubble_incoming), 0x106ACC)
        XCTAssertEqual(rgbValue(dayClassicPalette.linkBubble_outgoing), 0x004DBD)
    }

    func testDayClassicShadesFollowRecolorMapping() {
        XCTAssertEqual(rgbValue(dayClassicPalette.accentSelect), 0x4E99DA)
        XCTAssertEqual(rgbValue(dayClassicPalette.badge), 0x4BABF7)
        XCTAssertEqual(rgbValue(dayClassicPalette.fileActivityBackground), 0x4BABF7)
        XCTAssertEqual(rgbValue(dayClassicPalette.fileActivityBackgroundBubble_incoming), 0x349FFF)
        XCTAssertEqual(rgbValue(dayClassicPalette.waveformForeground), 0x4BABF7)
        XCTAssertEqual(rgbValue(dayClassicPalette.waveformBackgroundBubble_incoming), 0x349FFF)
        XCTAssertEqual(rgbValue(dayClassicPalette.revealAction_neutral1_background), 0x4591FF)
        XCTAssertEqual(rgbValue(dayClassicPalette.focusAnimationColor), 0x6CB2F7)
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
