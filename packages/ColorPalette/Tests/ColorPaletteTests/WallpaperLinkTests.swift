import XCTest
@testable import ColorPalette

final class WallpaperLinkTests: XCTestCase {
    func testImpulsemWallpaperLinkRoundTrip() {
        let link: String = "https://o.impulsem.net/bg/cool-slug?mode=blur&intensity=50"
        guard let wallpaper = PaletteWallpaper(link) else {
            XCTFail("Wallpaper link on the ImpulseM host must parse")
            return
        }
        XCTAssertEqual(wallpaper, .url(link))
        XCTAssertEqual(wallpaper.toString, link)
        XCTAssertEqual(PaletteWallpaper(wallpaper.toString), wallpaper)
    }

    func testImpulsemWallpaperLinkWithoutSchemeIsAccepted() {
        let link: String = "o.impulsem.net/bg/cool-slug"
        XCTAssertEqual(PaletteWallpaper(link), .url(link))
    }

    func testLegacyTelegramWallpaperLinkIsStillAccepted() {
        let link: String = "https://t.me/bg/cool-slug"
        guard let wallpaper = PaletteWallpaper(link) else {
            XCTFail("Legacy wallpaper link must still parse")
            return
        }
        XCTAssertEqual(wallpaper, .url(link))
        XCTAssertEqual(PaletteWallpaper(wallpaper.toString), wallpaper)
    }

    func testBuiltinAndNoneWallpaperRoundTrip() {
        XCTAssertEqual(PaletteWallpaper("builtin")?.toString, "builtin")
        XCTAssertEqual(PaletteWallpaper("none")?.toString, "none")
    }
}
