import XCTest
@testable import TelegramLinks

final class ContactTokenLinkTests: XCTestCase {
    private let linkHost: String = "o.example.org"


    func testConfiguredShortHostIsAccepted() {
        let link: ContactTokenLink? = parseContactTokenLink("https://o.example.org/contact/XXXX:YYYZZZ?free=AABBCC", linkHost: linkHost)
        XCTAssertEqual(link, ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: "AABBCC"))
    }


    func testConfiguredShortHostWithoutSchemeIsAccepted() {
        let link: ContactTokenLink? = parseContactTokenLink("o.example.org/contact/XXXX:YYYZZZ", linkHost: linkHost)
        XCTAssertEqual(link, ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: nil))
    }


    func testUpstreamHostsStillAccepted() {
        let domains: [String] = ["t.me", "telegram.me", "telegram.dog"]
        for domain in domains {
            let link: ContactTokenLink? = parseContactTokenLink("https://\(domain)/contact/XXXX:YYYZZZ", linkHost: nil)
            XCTAssertEqual(link, ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: nil), domain)
        }
    }


    func testConfiguredShortHostRejectsNonContactPaths() {
        XCTAssertNil(parseContactTokenLink("https://o.example.org/alice", linkHost: linkHost))
        XCTAssertNil(parseContactTokenLink("https://o.example.org/contact/XXXX/YYYY", linkHost: linkHost))
        XCTAssertNil(parseContactTokenLink("https://o.example.org/contact/", linkHost: linkHost))
    }


    func testOtherHostsAreRejected() {
        XCTAssertNil(parseContactTokenLink("https://example.org/contact/XXXX:YYYZZZ", linkHost: linkHost))
        XCTAssertNil(parseContactTokenLink("https://example.com/contact/XXXX:YYYZZZ", linkHost: linkHost))
    }


    func testShortHostIsRejectedWhenNoLinkHostIsConfigured() {
        XCTAssertNil(parseContactTokenLink("https://o.example.org/contact/XXXX:YYYZZZ", linkHost: nil))
    }


    func testConfiguredShortHostIsRoutedAsContactTokenWithNavigation() {
        let options: InAppLinkParsingOptions = InAppLinkParsingOptions(hasContext: true, hasOpenInfo: true, linkHost: linkHost)
        guard case let .contactToken(_, token, freeToken) = parseInAppLink("https://o.example.org/contact/XXXX:YYYZZZ?free=AABBCC" as NSString, options: options) else {
            return XCTFail("Expected contact token link from the configured short host")
        }
        XCTAssertEqual(token, "XXXX:YYYZZZ")
        XCTAssertEqual(freeToken, "AABBCC")
    }
}
