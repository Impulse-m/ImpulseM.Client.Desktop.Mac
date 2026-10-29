import Foundation
import ImpulseProxy
import ImpulseTransport


/// Feeds the transport the route of a `ProxyController`: nil for a direct connection, the HTTP inbound of the running core,
/// and the blackhole route while the proxy is on but the core does not run, so nothing goes out unproxied.
final class ImpulseProxyRouteAdapter: ImpulseProxyRouteSource, Sendable {
    private let controller: ProxyController


    init(
        controller: ProxyController
    ) {
        self.controller = controller
    }


    var currentRoute: ImpulseProxyRoute? {
        let route: ProxyRoute = controller.route
        let access: ProxyAccess? = controller.runtime?.httpAccess
        let selection: ProxySelection = ProxySelector.select(
            route: route,
            access: access
        )
        switch selection {
        case .direct:
            return nil

        case .http(let endpoint, let credentials):
            return ImpulseProxyRoute(
                host: endpoint.host,
                port: endpoint.port,
                username: credentials?.user,
                password: credentials?.password
            )
        }
    }


    func observe(
        _ handler: @escaping @Sendable (Int) -> Void
    ) -> ImpulseProxyRouteObservation {
        let observation: ProxyObservation = controller.observeEpoch(handler)
        return ImpulseProxyRouteObservationHandle(
            observation: observation
        )
    }
}


/// Cancels the epoch observer of the controller behind a route observation.
private final class ImpulseProxyRouteObservationHandle: ImpulseProxyRouteObservation {
    private let observation: ProxyObservation


    init(
        observation: ProxyObservation
    ) {
        self.observation = observation
    }


    func cancel() {
        observation.cancel()
    }
}
