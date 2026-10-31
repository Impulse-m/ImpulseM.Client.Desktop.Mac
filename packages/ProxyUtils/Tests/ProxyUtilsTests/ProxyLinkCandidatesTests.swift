import XCTest
import ProxyUtils


final class ProxyLinkCandidatesTests: XCTestCase {
    private static let vlessLine: String = "vless://11111111-2222-3333-4444-555555555555@example.com:443?security=none#Alpha"


    func testVlessLineIsCandidate() {
        XCTAssertEqual(ProxyLinkCandidates.extract(text: ProxyLinkCandidatesTests.vlessLine), [.vless(ProxyLinkCandidatesTests.vlessLine)])
    }


    func testVlessSchemeIsCaseInsensitive() {
        let upper: String = "VLESS://11111111-2222-3333-4444-555555555555@example.com:443#Beta"
        XCTAssertEqual(ProxyLinkCandidates.extract(text: upper), [.vless(upper)])
    }


    func testHttpsSubscriptionIsCandidate() throws {
        let url: URL = try XCTUnwrap(URL(string: "https://panel.example.com/sub/token"))
        XCTAssertEqual(ProxyLinkCandidates.extract(text: "https://panel.example.com/sub/token"), [.subscription(url)])
    }


    func testHttpSubscriptionIsCandidate() throws {
        let url: URL = try XCTUnwrap(URL(string: "http://example.com/sub"))
        XCTAssertEqual(ProxyLinkCandidates.extract(text: "  http://example.com/sub  "), [.subscription(url)])
    }


    func testTelegramProxyLinksAreNotCandidates() {
        let text: String = [
            "tg://proxy?server=1.2.3.4&port=443&secret=abcd",
            "tg://socks?server=1.2.3.4&port=1080",
            "im://proxy?server=1.2.3.4&port=443&secret=abcd",
            "https://t.me/proxy?server=1.2.3.4&port=443&secret=abcd",
            "https://t.me/socks?server=1.2.3.4&port=1080",
            "https://telegram.me/socks?server=1.2.3.4&port=1080",
        ].joined(separator: "\n")
        XCTAssertEqual(ProxyLinkCandidates.extract(text: text), [])
    }


    func testMixedTextKeepsOrderAndSkipsOtherLines() throws {
        let subscription: URL = try XCTUnwrap(URL(string: "https://example.com/sub"))
        let text: String = [
            "Hello there",
            "vless://a@h:1#x",
            "  https://example.com/sub  ",
            "",
            "tg://proxy?server=a&port=1",
            "vless://b@h:2#y",
        ].joined(separator: "\n")
        XCTAssertEqual(
            ProxyLinkCandidates.extract(text: text),
            [
                .vless("vless://a@h:1#x"),
                .subscription(subscription),
                .vless("vless://b@h:2#y"),
            ]
        )
    }


    func testUrlWithWhitespaceInsideIsNotCandidate() {
        XCTAssertEqual(ProxyLinkCandidates.extract(text: "https://example.com/a b"), [])
    }


    func testEmptyTextHasNoCandidates() {
        XCTAssertEqual(ProxyLinkCandidates.extract(text: ""), [])
    }
}
