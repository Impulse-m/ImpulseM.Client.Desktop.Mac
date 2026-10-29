import XCTest
@testable import TelegramLinks

final class ContactTokenLinkTests: XCTestCase {
    func testImpulseMShortHostIsAccepted() {
        let link: ContactTokenLink? = parseContactTokenLink("https://o.impulsem.net/contact/XXXX:YYYZZZ?free=AABBCC")
        XCTAssertEqual(link, ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: "AABBCC"))
    }

    func testImpulseMShortHostWithoutSchemeIsAccepted() {
        let link: ContactTokenLink? = parseContactTokenLink("o.impulsem.net/contact/XXXX:YYYZZZ")
        XCTAssertEqual(link, ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: nil))
    }

    func testUpstreamHostsStillAccepted() {
        let domains: [String] = ["t.me", "telegram.me", "telegram.dog"]
        for domain in domains {
            let link: ContactTokenLink? = parseContactTokenLink("https://\(domain)/contact/XXXX:YYYZZZ")
            XCTAssertEqual(link, ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: nil), domain)
        }
    }

    func testImpulseMShortHostRejectsNonContactPaths() {
        XCTAssertNil(parseContactTokenLink("https://o.impulsem.net/alice"))
        XCTAssertNil(parseContactTokenLink("https://o.impulsem.net/contact/XXXX/YYYY"))
        XCTAssertNil(parseContactTokenLink("https://o.impulsem.net/contact/"))
    }

    func testOtherHostsAreRejected() {
        XCTAssertNil(parseContactTokenLink("https://impulsem.net/contact/XXXX:YYYZZZ"))
        XCTAssertNil(parseContactTokenLink("https://example.com/contact/XXXX:YYYZZZ"))
    }

    func testImpulseMShortHostIsRoutedAsContactTokenWithNavigation() {
        let options: InAppLinkParsingOptions = InAppLinkParsingOptions(hasContext: true, hasOpenInfo: true)
        guard case let .contactToken(_, token, freeToken) = parseInAppLink("https://o.impulsem.net/contact/XXXX:YYYZZZ?free=AABBCC" as NSString, options: options) else {
            return XCTFail("Expected contact token link from the ImpulseM short host")
        }
        XCTAssertEqual(token, "XXXX:YYYZZZ")
        XCTAssertEqual(freeToken, "AABBCC")
    }
}
