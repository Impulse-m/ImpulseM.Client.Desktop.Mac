import ImpulseProxy


public extension ImpulseProxy.ImpulseProxyState {
    /// True when the record has a selected server, a manual server, or a subscription with at least one server.
    var hasAnyServer: Bool {
        if selectedId != nil {
            return true
        }
        if !manual.isEmpty {
            return true
        }
        return subscriptions.contains { (subscription: ImpulseProxy.ImpulseProxyState.Subscription) -> Bool in
            return !subscription.servers.isEmpty
        }
    }
}
