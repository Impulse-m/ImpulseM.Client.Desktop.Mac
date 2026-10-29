import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ProxyUI

func installProxyUIHooks() {
    installProxyHooks(.init(
        currentContext: {
            return appDelegate?.currentContext
        },
        impulseProxyController: {
            return ImpulseProxyRuntime.shared.controller
        },
        subscriptionSession: { () -> URLSession in
            return ImpulseProxyRuntime.shared.subscriptionSession()
        }
    ))
}
