import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import ImpulseProxy


typealias ImpulseProxyChange = (inout ImpulseProxy.ImpulseProxyState) -> Void


/// Reads and writes the ImpulseM proxy record kept in the account manager shared data.
/// The record is the TelegramCore model; the UI works on the ImpulseProxy model. Both share the JSON shape `{"v":1,...}`,
/// so the conversion goes through JSON.
enum ImpulseProxySettingsStore {
    static func signal(
        accountManager: AccountManager<TelegramAccountManagerTypes>
    ) -> Signal<ImpulseProxy.ImpulseProxyState, NoError> {
        return accountManager.sharedData(keys: [SharedDataKeys.proxySettings]) |> map { view in
            return ImpulseProxySettingsStore.read(view.entries[SharedDataKeys.proxySettings])
        }
    }


    /// Applies a change in one account manager transaction, then hands the result to the running controller, which
    /// restarts the core when the enabled flag, the selected server or a core-affecting setting changed.
    static func update(
        accountManager: AccountManager<TelegramAccountManagerTypes>,
        change: @escaping ImpulseProxyChange
    ) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> ImpulseProxy.ImpulseProxyState in
            var result: ImpulseProxy.ImpulseProxyState = ImpulseProxy.ImpulseProxyState()
            transaction.updateSharedData(SharedDataKeys.proxySettings, { (current: PreferencesEntry?) -> PreferencesEntry? in
                var state: ImpulseProxy.ImpulseProxyState = ImpulseProxySettingsStore.read(current)
                change(&state)
                result = state
                guard let record: TelegramCore.ImpulseProxyState = ImpulseProxySettingsStore.write(state) else {
                    return current
                }
                return PreferencesEntry(record)
            })
            return result
        } |> deliverOnMainQueue |> map { (state: ImpulseProxy.ImpulseProxyState) -> Void in
            if let controller: ProxyController = ProxyHooks.installed?.impulseProxyController() {
                controller.update { (next: inout ImpulseProxy.ImpulseProxyState) -> Void in
                    next = state
                }
            }
        }
    }


    /// Writes the record in one account manager transaction and does not touch the running controller.
    /// The runtime uses it to persist what the controller already holds.
    static func save(
        accountManager: AccountManager<TelegramAccountManagerTypes>,
        state: ImpulseProxy.ImpulseProxyState
    ) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.updateSharedData(SharedDataKeys.proxySettings, { (current: PreferencesEntry?) -> PreferencesEntry? in
                guard let record: TelegramCore.ImpulseProxyState = ImpulseProxySettingsStore.write(state) else {
                    return current
                }
                return PreferencesEntry(record)
            })
        }
    }


    private static func read(
        _ entry: PreferencesEntry?
    ) -> ImpulseProxy.ImpulseProxyState {
        guard let record: TelegramCore.ImpulseProxyState = entry?.get(TelegramCore.ImpulseProxyState.self) else {
            return ImpulseProxy.ImpulseProxyState()
        }
        guard let data: Data = try? JSONEncoder().encode(record) else {
            return ImpulseProxy.ImpulseProxyState()
        }
        return ImpulseProxy.ImpulseProxyState.decode(json: String(decoding: data, as: UTF8.self))
    }


    private static func write(
        _ state: ImpulseProxy.ImpulseProxyState
    ) -> TelegramCore.ImpulseProxyState? {
        guard let json: String = try? state.encodedJSON() else {
            return nil
        }
        return try? JSONDecoder().decode(TelegramCore.ImpulseProxyState.self, from: Data(json.utf8))
    }
}


/// Every server the user can pick: the manual servers first, then the servers of each subscription.
func impulseProxyAllServers(
    _ state: ImpulseProxy.ImpulseProxyState
) -> [ImpulseProxy.ImpulseProxyState.Server] {
    var servers: [ImpulseProxy.ImpulseProxyState.Server] = state.manual
    for subscription: ImpulseProxy.ImpulseProxyState.Subscription in state.subscriptions {
        servers.append(contentsOf: subscription.servers)
    }
    return servers
}


/// Clears the selection when the selected server no longer exists. The controller then fails closed until a new server is picked.
func impulseProxyClearMissingSelection(
    _ state: inout ImpulseProxy.ImpulseProxyState
) {
    guard let selected: String = state.selectedId else {
        return
    }
    let servers: [ImpulseProxy.ImpulseProxyState.Server] = impulseProxyAllServers(state)
    if !servers.contains(where: { (server: ImpulseProxy.ImpulseProxyState.Server) -> Bool in
        return server.id == selected
    }) {
        state.selectedId = nil
    }
}


/// Adds a subscription, or replaces the one with the same id.
func impulseProxyReplaceSubscription(
    _ state: inout ImpulseProxy.ImpulseProxyState,
    _ subscription: ImpulseProxy.ImpulseProxyState.Subscription
) {
    if let index: Int = state.subscriptions.firstIndex(where: { (item: ImpulseProxy.ImpulseProxyState.Subscription) -> Bool in
        return item.id == subscription.id
    }) {
        state.subscriptions[index] = subscription
    } else {
        state.subscriptions.append(subscription)
    }
}
