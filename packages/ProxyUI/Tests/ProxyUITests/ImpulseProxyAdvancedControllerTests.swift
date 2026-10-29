import XCTest
import ImpulseProxy
import ProxyUI


final class ImpulseProxyAdvancedControllerTests: XCTestCase {
    func testAdvancedDefaultsMatchContract() {
        let advanced: ImpulseProxyState.Advanced = ImpulseProxyState.Advanced()

        XCTAssertEqual(advanced.fragmentMode, "off")
        XCTAssertEqual(advanced.fragmentPackets, "tlshello")
        XCTAssertEqual(advanced.fragmentLength, "100-200")
        XCTAssertEqual(advanced.fragmentInterval, "10-20")
        XCTAssertTrue(advanced.fragmentFromLink)
        XCTAssertEqual(advanced.fingerprint, "")
        XCTAssertFalse(advanced.muxEnabled)
        XCTAssertEqual(advanced.muxConcurrency, 8)
        XCTAssertEqual(advanced.keepAliveIdle, 0)
        XCTAssertEqual(advanced.keepAliveInterval, 0)
        XCTAssertFalse(advanced.tcpFastOpen)
        XCTAssertEqual(advanced.tcpMaxSeg, 0)
        XCTAssertEqual(advanced.dnsMode, "system")
        XCTAssertEqual(advanced.dnsCustom, "")
        XCTAssertEqual(advanced.pingMode, "batch")
        XCTAssertEqual(advanced.pingPauseMillis, 0)
        XCTAssertEqual(advanced.pingTimeoutSeconds, 5)
        XCTAssertEqual(advanced.pingUrl, "https://www.gstatic.com/generate_204")
        XCTAssertTrue(advanced.pingSkipWhileConnected)
    }


    func testPingSettingsDoNotRestartCore() {
        let previous: ImpulseProxyState.Advanced = ImpulseProxyState.Advanced()

        var pingMode: ImpulseProxyState.Advanced = previous
        pingMode.pingMode = "sequential"
        XCTAssertFalse(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: pingMode))

        var pingPause: ImpulseProxyState.Advanced = previous
        pingPause.pingPauseMillis = 500
        XCTAssertFalse(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: pingPause))

        var pingTimeout: ImpulseProxyState.Advanced = previous
        pingTimeout.pingTimeoutSeconds = 12
        XCTAssertFalse(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: pingTimeout))

        var pingUrl: ImpulseProxyState.Advanced = previous
        pingUrl.pingUrl = "https://example.com/204"
        XCTAssertFalse(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: pingUrl))

        var pingSkip: ImpulseProxyState.Advanced = previous
        pingSkip.pingSkipWhileConnected = false
        XCTAssertFalse(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: pingSkip))
    }


    func testCoreSettingsRestartCore() {
        let previous: ImpulseProxyState.Advanced = ImpulseProxyState.Advanced()

        var fragmentMode: ImpulseProxyState.Advanced = previous
        fragmentMode.fragmentMode = "classic"
        XCTAssertTrue(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: fragmentMode))

        var fingerprint: ImpulseProxyState.Advanced = previous
        fingerprint.fingerprint = "firefox"
        XCTAssertTrue(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: fingerprint))

        var mux: ImpulseProxyState.Advanced = previous
        mux.muxEnabled = true
        XCTAssertTrue(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: mux))

        var fastOpen: ImpulseProxyState.Advanced = previous
        fastOpen.tcpFastOpen = true
        XCTAssertTrue(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: fastOpen))

        var dns: ImpulseProxyState.Advanced = previous
        dns.dnsMode = "google"
        XCTAssertTrue(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: dns))

        var keepAlive: ImpulseProxyState.Advanced = previous
        keepAlive.keepAliveIdle = 60
        XCTAssertTrue(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: keepAlive))

        var fromLink: ImpulseProxyState.Advanced = previous
        fromLink.fragmentFromLink = false
        XCTAssertTrue(ImpulseProxyAdvancedRules.restartRequired(previous: previous, next: fromLink))
    }


    func testNumbersAcceptOnlyTheSanitizerRange() {
        XCTAssertEqual(ImpulseProxyAdvancedRules.parseNumber("12"), 12)
        XCTAssertNil(ImpulseProxyAdvancedRules.parseNumber(""))
        XCTAssertNil(ImpulseProxyAdvancedRules.parseNumber("-1"))
        XCTAssertNil(ImpulseProxyAdvancedRules.parseNumber("1a"))

        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptNumber("128", at: \.muxConcurrency), 128)
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptNumber("129", at: \.muxConcurrency))
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptNumber("0", at: \.muxConcurrency))

        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptNumber("0", at: \.tcpMaxSeg), 0)
        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptNumber("64", at: \.tcpMaxSeg), 64)
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptNumber("63", at: \.tcpMaxSeg))
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptNumber("1461", at: \.tcpMaxSeg))

        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptNumber("30", at: \.pingTimeoutSeconds), 30)
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptNumber("0", at: \.pingTimeoutSeconds))
    }


    func testTextAcceptsOnlyTheSanitizerRules() {
        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptText("100-200", at: \.fragmentLength), "100-200")
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptText("abc", at: \.fragmentLength))
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptText("", at: \.fragmentLength))

        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptText("tlshello", at: \.fragmentPackets), "tlshello")
        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptText("1-3", at: \.fragmentPackets), "1-3")
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptText("custom", at: \.fragmentPackets))

        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptText("https://1.1.1.1/dns-query", at: \.dnsCustom), "https://1.1.1.1/dns-query")
        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptText("8.8.4.4", at: \.dnsCustom), "8.8.4.4")
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptText("8.8.4", at: \.dnsCustom))

        XCTAssertEqual(ImpulseProxyAdvancedRules.acceptText("https://example.com/204", at: \.pingUrl), "https://example.com/204")
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptText("http://example.com/204", at: \.pingUrl))
        XCTAssertNil(ImpulseProxyAdvancedRules.acceptText("https://exa mple.com", at: \.pingUrl))
    }
}
