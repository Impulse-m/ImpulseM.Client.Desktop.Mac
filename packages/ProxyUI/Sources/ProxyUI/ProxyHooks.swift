import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import ImpulseProxy

public struct ProxyHooks {
    public let currentContext: () -> (any AccountContextProtocol)?
    /// The running ImpulseM proxy controller, or nil while the app has not created one.
    public let impulseProxyController: () -> ProxyController?
    /// The session used to download subscriptions. It should route through the proxy when the main transport is proxied.
    public let subscriptionSession: () -> URLSession

    public init(
        currentContext: @escaping () -> (any AccountContextProtocol)?,
        impulseProxyController: @escaping () -> ProxyController? = { nil },
        subscriptionSession: @escaping () -> URLSession = { URLSession.shared }
    ) {
        self.currentContext = currentContext
        self.impulseProxyController = impulseProxyController
        self.subscriptionSession = subscriptionSession
    }

    private static var value: ProxyHooks?

    public static var shared: ProxyHooks {
        guard let value = value else {
            preconditionFailure("ProxyHooks not installed")
        }
        return value
    }

    /// The installed hooks, or nil before installation. Use it where the UI must not trap.
    public static var installed: ProxyHooks? {
        return value
    }

    public static func install(_ hooks: ProxyHooks) {
        self.value = hooks
    }
}

public func installProxyHooks(_ hooks: ProxyHooks) {
    ProxyHooks.install(hooks)
}
