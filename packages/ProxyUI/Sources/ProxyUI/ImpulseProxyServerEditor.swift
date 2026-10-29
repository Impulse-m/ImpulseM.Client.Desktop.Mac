import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import InputDataUI
import AlertsUI
import ImpulseProxy


private let impulseProxyAddInputId: InputDataIdentifier = InputDataIdentifier("proxy.add.input")
private let impulseProxyAddDescription: String = "Paste a vless:// link or an https:// subscription URL."
private let impulseProxyAddPlaceholder: String = "vless:// or https://"
private let impulseProxyAddInvalidText: String = "Enter a vless:// link or an https:// subscription URL."


/// Adds one or more manual servers from `vless://` lines, or one subscription from an `https://` URL.
public func addProxyController(accountManager: AccountManager<TelegramAccountManagerTypes>) -> InputDataController {
    let actionsDisposable: DisposableSet = DisposableSet()
    let entries: [InputDataEntry] = impulseProxyAddEntries()

    let controller: InputDataController = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: strings().proxySettingsAddProxy, validateData: { (data: [InputDataIdentifier: InputDataValue]) -> InputDataValidation in
        let value: String = (data[impulseProxyAddInputId]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return .fail(.doSomething(next: { (finish: @escaping (InputDataValidation) -> Void) -> Void in
            impulseProxyAddValue(accountManager: accountManager, actionsDisposable: actionsDisposable, value: value, finish: finish)
        }))
    }, afterDisappear: {
        actionsDisposable.dispose()
    }, removeAfterDisappear: true, hasDone: true, identifier: "proxy.add")

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
}


/// Refreshes one subscription. A failed refresh keeps the previous servers and stores the error.
func impulseProxyRefreshSubscription(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    subscription: ImpulseProxy.ImpulseProxyState.Subscription
) {
    Task {
        let result: ImpulseProxy.ImpulseProxyState.Subscription? = try? await impulseProxyFetcher().fetch(
            url: subscription.url,
            previous: subscription,
            nowMillis: impulseProxyNowMillis()
        )
        guard let fetched: ImpulseProxy.ImpulseProxyState.Subscription = result else {
            return
        }
        _ = ImpulseProxySettingsStore.update(accountManager: accountManager, change: { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
            impulseProxyReplaceSubscription(&state, fetched)
            impulseProxyClearMissingSelection(&state)
        }).start()
    }
}


private func impulseProxyAddEntries() -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    entries.append(.sectionId(0, type: .normal))
    entries.append(.desc(sectionId: 0, index: 0, text: .plain(impulseProxyAddDescription), data: InputDataGeneralTextData(viewType: .textTopItem)))
    entries.append(.input(sectionId: 0, index: 1, value: .string(""), error: nil, identifier: impulseProxyAddInputId, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: impulseProxyAddPlaceholder, filter: { (text: String) -> String in
        return text
    }, limit: 4096))
    entries.append(.sectionId(0, type: .normal))
    return entries
}


private func impulseProxyAddValue(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    actionsDisposable: DisposableSet,
    value: String,
    finish: @escaping (InputDataValidation) -> Void
) {
    switch ProxyLinks.detectInputKind(text: value) {
    case .links:
        let servers: [ImpulseProxy.ImpulseProxyState.Server] = ProxyLinks.parseLinks(text: value, converter: impulseProxyConverter())
        if servers.isEmpty {
            alert(for: mainWindow, info: impulseProxyAddInvalidText)
            finish(.fail(.none))
            return
        }
        actionsDisposable.add(ImpulseProxySettingsStore.update(accountManager: accountManager, change: { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
            for server: ImpulseProxy.ImpulseProxyState.Server in servers {
                if !state.manual.contains(where: { (item: ImpulseProxy.ImpulseProxyState.Server) -> Bool in
                    return item.id == server.id
                }) {
                    state.manual.append(server)
                }
            }
        }).start())
        finish(.success(.navigationBack))
    case .subscription:
        impulseProxyAddSubscription(accountManager: accountManager, url: value, completion: { (error: String?) -> Void in
            if let error: String = error {
                alert(for: mainWindow, info: error)
                finish(.fail(.none))
            } else {
                finish(.success(.navigationBack))
            }
        })
    case .unknown:
        alert(for: mainWindow, info: impulseProxyAddInvalidText)
        finish(.fail(.none))
    }
}


private func impulseProxyAddSubscription(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    url: String,
    completion: @escaping (String?) -> Void
) {
    Task {
        let result: ImpulseProxy.ImpulseProxyState.Subscription? = try? await impulseProxyFetcher().fetch(
            url: url,
            previous: nil,
            nowMillis: impulseProxyNowMillis()
        )
        guard let fetched: ImpulseProxy.ImpulseProxyState.Subscription = result else {
            DispatchQueue.main.async {
                completion("err:network")
            }
            return
        }
        if let error: String = fetched.lastError {
            DispatchQueue.main.async {
                completion(error)
            }
            return
        }
        _ = ImpulseProxySettingsStore.update(accountManager: accountManager, change: { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
            impulseProxyReplaceSubscription(&state, fetched)
        }).start()
        DispatchQueue.main.async {
            completion(nil)
        }
    }
}


private func impulseProxyFetcher() -> ProxySubscriptionFetcher {
    let session: URLSession = ProxyHooks.installed?.subscriptionSession() ?? URLSession.shared
    return ProxySubscriptionFetcher(
        transport: ProxySubscriptionSessionTransport(session: session),
        converter: impulseProxyConverter()
    )
}


private func impulseProxyConverter() -> LibXrayClient {
    return LibXrayClient(bridge: LibXrayCGoBridge())
}


private func impulseProxyNowMillis() -> Int64 {
    return Int64(Date().timeIntervalSince1970 * 1000)
}
