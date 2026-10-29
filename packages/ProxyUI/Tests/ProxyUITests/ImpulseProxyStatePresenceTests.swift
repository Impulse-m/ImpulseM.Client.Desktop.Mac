import XCTest
import ImpulseProxy
@testable import ProxyUI


final class ImpulseProxyStatePresenceTests: XCTestCase {
    private func server(
        id: String
    ) -> ImpulseProxy.ImpulseProxyState.Server {
        return ImpulseProxy.ImpulseProxyState.Server(
            id: id,
            name: "name",
            host: "example.org",
            port: 443,
            network: "tcp",
            security: "none",
            outboundJson: "{}"
        )
    }


    func testEmptyRecordHasNoServer() {
        let state: ImpulseProxy.ImpulseProxyState = ImpulseProxy.ImpulseProxyState()
        XCTAssertFalse(state.hasAnyServer)
    }


    func testSelectedIdAloneCountsAsServer() {
        let state: ImpulseProxy.ImpulseProxyState = ImpulseProxy.ImpulseProxyState(selectedId: "a")
        XCTAssertTrue(state.hasAnyServer)
    }


    func testManualServerCountsAsServer() {
        let state: ImpulseProxy.ImpulseProxyState = ImpulseProxy.ImpulseProxyState(manual: [server(id: "m")])
        XCTAssertTrue(state.hasAnyServer)
    }


    func testSubscriptionWithServersCountsAsServer() {
        let subscription: ImpulseProxy.ImpulseProxyState.Subscription = ImpulseProxy.ImpulseProxyState.Subscription(
            id: "s",
            url: "https://example.org/sub",
            servers: [server(id: "x")]
        )
        let state: ImpulseProxy.ImpulseProxyState = ImpulseProxy.ImpulseProxyState(subscriptions: [subscription])
        XCTAssertTrue(state.hasAnyServer)
    }


    func testSubscriptionWithoutServersHasNoServer() {
        let subscription: ImpulseProxy.ImpulseProxyState.Subscription = ImpulseProxy.ImpulseProxyState.Subscription(
            id: "s",
            url: "https://example.org/sub",
            servers: []
        )
        let state: ImpulseProxy.ImpulseProxyState = ImpulseProxy.ImpulseProxyState(subscriptions: [subscription])
        XCTAssertFalse(state.hasAnyServer)
    }
}
