import XCTest
@testable import ApiCredentials


final class ImpulseBrandTests: XCTestCase {
    func testConfiguredBuildSettingIsReturned() {
        let info: [String: Any] = ["IMPULSEM_RPC_URL": "https://rpc.example.org"]
        XCTAssertEqual(ImpulseBrand.buildSetting("IMPULSEM_RPC_URL", in: info), "https://rpc.example.org")
    }


    func testMissingEmptyAndUnexpandedBuildSettingsAreNotConfigured() {
        XCTAssertNil(ImpulseBrand.buildSetting("IMPULSEM_RPC_URL", in: nil))
        XCTAssertNil(ImpulseBrand.buildSetting("IMPULSEM_RPC_URL", in: [:]))
        XCTAssertNil(ImpulseBrand.buildSetting("IMPULSEM_RPC_URL", in: ["IMPULSEM_RPC_URL": ""]))
        XCTAssertNil(ImpulseBrand.buildSetting("IMPULSEM_RPC_URL", in: ["IMPULSEM_RPC_URL": "   "]))
        XCTAssertNil(ImpulseBrand.buildSetting("IMPULSEM_RPC_URL", in: ["IMPULSEM_RPC_URL": "$(IMPULSEM_RPC_URL)"]))
    }


    func testBuildSettingIsTrimmed() {
        let info: [String: Any] = ["IMPULSEM_LINK_HOST": " o.example.org\n"]
        XCTAssertEqual(ImpulseBrand.buildSetting("IMPULSEM_LINK_HOST", in: info), "o.example.org")
    }


    func testLinkHostIsLowercasedWithoutSchemeOrSlashes() {
        XCTAssertEqual(ImpulseBrand.normalizedLinkHost("https://O.Example.org/"), "o.example.org")
        XCTAssertEqual(ImpulseBrand.normalizedLinkHost("HTTP://o.example.org///"), "o.example.org")
        XCTAssertEqual(ImpulseBrand.normalizedLinkHost("  o.example.org  "), "o.example.org")
    }


    func testEmptyLinkHostIsNotConfigured() {
        XCTAssertNil(ImpulseBrand.normalizedLinkHost(nil))
        XCTAssertNil(ImpulseBrand.normalizedLinkHost(""))
        XCTAssertNil(ImpulseBrand.normalizedLinkHost("https:///"))
    }


    func testBaseUrlsLoseSurroundingWhitespaceAndTrailingSlashes() {
        XCTAssertEqual(ImpulseBrand.normalizedBaseUrl("https://rpc.example.org/"), "https://rpc.example.org")
        XCTAssertEqual(ImpulseBrand.normalizedBaseUrl(" https://site.example.org// \n"), "https://site.example.org")
        XCTAssertEqual(ImpulseBrand.normalizedBaseUrl("https://feeds.example.org/updates"), "https://feeds.example.org/updates")
    }


    func testEmptyBaseUrlIsNotConfigured() {
        XCTAssertNil(ImpulseBrand.normalizedBaseUrl(nil))
        XCTAssertNil(ImpulseBrand.normalizedBaseUrl("   "))
        XCTAssertNil(ImpulseBrand.normalizedBaseUrl("/"))
    }


    func testSiteLinkJoinsPathToConfiguredSite() {
        XCTAssertEqual(ImpulseBrand.siteLink(path: "/privacy", siteUrl: "https://site.example.org"), "https://site.example.org/privacy")
        XCTAssertEqual(ImpulseBrand.siteLink(path: "tos/stars", siteUrl: "https://site.example.org"), "https://site.example.org/tos/stars")
    }


    func testSiteLinkIsNilWithoutSite() {
        XCTAssertNil(ImpulseBrand.siteLink(path: "/privacy", siteUrl: nil))
    }


    func testSiteTokenBecomesLinkWhenSiteIsConfigured() {
        let text: String = "Read [Terms]({IMPULSEM_SITE_URL}/tos) now"
        XCTAssertEqual(ImpulseBrand.resolveSiteLinks(in: text, siteUrl: "https://site.example.org"), "Read [Terms](https://site.example.org/tos) now")
    }


    func testSiteTokenKeepsOnlyLabelWithoutSite() {
        let text: String = "Read [Terms]({IMPULSEM_SITE_URL}/tos) now"
        XCTAssertEqual(ImpulseBrand.resolveSiteLinks(in: text, siteUrl: nil), "Read Terms now")
    }


    func testBareSiteUrlResolvesOrVanishes() {
        let text: String = "{IMPULSEM_SITE_URL}/privacy-tpa"
        XCTAssertEqual(ImpulseBrand.resolveSiteLinks(in: text, siteUrl: "https://site.example.org"), "https://site.example.org/privacy-tpa")
        XCTAssertEqual(ImpulseBrand.resolveSiteLinks(in: text, siteUrl: nil), "")
    }


    func testTextWithoutSiteTokenIsUnchanged() {
        let text: String = "Plain text with [a link](https://other.example.org)"
        XCTAssertEqual(ImpulseBrand.resolveSiteLinks(in: text, siteUrl: nil), text)
    }
}
