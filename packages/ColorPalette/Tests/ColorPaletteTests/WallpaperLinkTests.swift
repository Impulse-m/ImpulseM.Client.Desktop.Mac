import XCTest
@testable import ColorPalette

final class WallpaperLinkTests: XCTestCase {
    private let linkHost: String = "o.example.org"


    func testConfiguredHostWallpaperLinkRoundTrip() {
        let link: String = "https://o.example.org/bg/cool-slug?mode=blur&intensity=50"
        guard let wallpaper = PaletteWallpaper(link, linkHost: linkHost) else {
            XCTFail("Wallpaper link on the configured host must parse")
            return
        }
        XCTAssertEqual(wallpaper, .url(link))
        XCTAssertEqual(wallpaper.toString, link)
        XCTAssertEqual(PaletteWallpaper(wallpaper.toString, linkHost: linkHost), wallpaper)
    }


    func testConfiguredHostWallpaperLinkWithoutSchemeIsAccepted() {
        let link: String = "o.example.org/bg/cool-slug"
        XCTAssertEqual(PaletteWallpaper(link, linkHost: linkHost), .url(link))
    }


    func testConfiguredHostWallpaperLinkIsRejectedWhenNoLinkHostIsConfigured() {
        XCTAssertNil(PaletteWallpaper("https://o.example.org/bg/cool-slug", linkHost: nil))
    }


    func testLegacyTelegramWallpaperLinkIsStillAccepted() {
        let link: String = "https://t.me/bg/cool-slug"
        guard let wallpaper = PaletteWallpaper(link, linkHost: nil) else {
            XCTFail("Legacy wallpaper link must still parse")
            return
        }
        XCTAssertEqual(wallpaper, .url(link))
        XCTAssertEqual(PaletteWallpaper(wallpaper.toString, linkHost: nil), wallpaper)
    }


    func testBuiltinAndNoneWallpaperRoundTrip() {
        XCTAssertEqual(PaletteWallpaper("builtin", linkHost: nil)?.toString, "builtin")
        XCTAssertEqual(PaletteWallpaper("none", linkHost: nil)?.toString, "none")
    }
}
