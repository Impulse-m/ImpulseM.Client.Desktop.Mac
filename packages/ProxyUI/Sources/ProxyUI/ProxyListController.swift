import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import GeneralRows
import InputDataUI
import AlertsUI
import ImpulseProxy


private let impulseProxyBlockedText: String = "Blocked: traffic waits for the proxy core"
private let impulseProxyTransportText: String = "Use for main traffic"
private let impulseProxyAdvancedText: String = "Advanced"
private let impulseProxyDeleteText: String = "Delete"
private let impulseProxyUpdateText: String = "Update"
private let impulseProxyMigrationText: String = "Telegram proxy settings were removed in ImpulseM. Add a server to use a proxy."
/// Proxied calls stay hidden in this build: the calls toggle is shown only when the calls relay is enabled.
private let impulseProxyCallsToggleVisible: Bool = false


private struct ImpulseProxyListState: Equatable {
    let settings: ImpulseProxy.ImpulseProxyState
    let migrationNoticePending: Bool
}


private struct ImpulseProxyRowKey: Equatable {
    let title: String
    let detail: String?
    let type: GeneralInteractedType
    let isEnabled: Bool
    let isAction: Bool
    let viewType: GeneralViewType
}


private struct ImpulseProxyRowSpec {
    let identifier: String
    let title: String
    let detail: String?
    let type: GeneralInteractedType
    let isEnabled: Bool
    let isAction: Bool
    let action: () -> Void
    let menuItems: (() -> [ContextMenuItem])?
}


private struct ImpulseProxyListArguments {
    let toggleEnabled: () -> Void
    let toggleTransport: () -> Void
    let toggleCalls: () -> Void
    let selectServer: (String) -> Void
    let deleteManual: (String) -> Void
    let deleteSubscription: (String) -> Void
    let refreshSubscription: (ImpulseProxy.ImpulseProxyState.Subscription) -> Void
    let addServer: () -> Void
    let openAdvanced: () -> Void
}


/// The ImpulseM proxy list: the enabled switch with the status, the main-traffic and calls toggles, the servers,
/// the subscriptions and the advanced page. `share` is kept for the existing callers and is not used.
public func proxyListController(accountManager: AccountManager<TelegramAccountManagerTypes>, network: Network, showUseCalls: Bool = true, share: @escaping([ProxyServerSettings]) -> Void = { _ in }, pushController: @escaping(ViewController) -> Void = { _ in }) -> ViewController {
    let actionsDisposable: DisposableSet = DisposableSet()
    let connectionTick: ValuePromise<Int> = ValuePromise(0, ignoreRepeated: false)

    if let observed: ProxyController = ProxyHooks.installed?.impulseProxyController() {
        observed.observeEpoch({ (epoch: Int) -> Void in
            connectionTick.set(epoch)
        })
    }

    let apply: (@escaping ImpulseProxyChange) -> Void = { (change: @escaping ImpulseProxyChange) -> Void in
        actionsDisposable.add(ImpulseProxySettingsStore.update(accountManager: accountManager, change: change).start())
    }

    let arguments: ImpulseProxyListArguments = ImpulseProxyListArguments(
        toggleEnabled: {
            apply { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
                if state.enabled {
                    state.enabled = false
                } else {
                    state.enabled = true
                    impulseProxyEnsureSelection(&state)
                }
            }
        },
        toggleTransport: {
            apply { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
                _ = state.setToggles(useForTransport: !state.useForTransport, useForCalls: state.useForCalls)
            }
        },
        toggleCalls: {
            apply { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
                _ = state.setToggles(useForTransport: state.useForTransport, useForCalls: !state.useForCalls)
            }
        },
        selectServer: { (serverId: String) -> Void in
            apply { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
                state.selectedId = serverId
            }
        },
        deleteManual: { (serverId: String) -> Void in
            apply { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
                state.manual.removeAll(where: { (server: ImpulseProxy.ImpulseProxyState.Server) -> Bool in
                    return server.id == serverId
                })
                impulseProxyClearMissingSelection(&state)
            }
        },
        deleteSubscription: { (subscriptionId: String) -> Void in
            apply { (state: inout ImpulseProxy.ImpulseProxyState) -> Void in
                state.subscriptions.removeAll(where: { (subscription: ImpulseProxy.ImpulseProxyState.Subscription) -> Bool in
                    return subscription.id == subscriptionId
                })
                impulseProxyClearMissingSelection(&state)
            }
        },
        refreshSubscription: { (subscription: ImpulseProxy.ImpulseProxyState.Subscription) -> Void in
            impulseProxyRefreshSubscription(accountManager: accountManager, subscription: subscription)
        },
        addServer: {
            pushController(addProxyController(accountManager: accountManager))
        },
        openAdvanced: {
            if let controller: ProxyController = ProxyHooks.installed?.impulseProxyController() {
                pushController(impulseProxyAdvancedController(proxy: controller))
            }
        }
    )

    let stateSignal: Signal<ImpulseProxyListState, NoError> = combineLatest(ImpulseProxySettingsStore.signal(accountManager: accountManager), proxySettingsMigrationNoticePending(accountManager: accountManager)) |> map { (values: (ImpulseProxy.ImpulseProxyState, Bool)) -> ImpulseProxyListState in
        return ImpulseProxyListState(settings: values.0, migrationNoticePending: values.1)
    }

    let dataSignal: Signal<InputDataSignalValue, NoError> = combineLatest(queue: prepareQueue, stateSignal, network.connectionStatus, connectionTick.get(), appearanceSignal) |> map { values -> InputDataSignalValue in
        let controller: ProxyController? = ProxyHooks.installed?.impulseProxyController()
        let statusText: String = impulseProxyStatusText(settings: values.0.settings, controller: controller, connection: values.1)
        let entries: [InputDataEntry] = impulseProxyListEntries(state: values.0, statusText: statusText, showUseCalls: showUseCalls, hasAdvanced: controller != nil, arguments: arguments)
        return InputDataSignalValue(entries: entries)
    }

    let controller: InputDataController = InputDataController(dataSignal: dataSignal, title: strings().proxySettingsTitle, afterDisappear: {
        _ = dismissProxySettingsMigrationNotice(accountManager: accountManager).start()
        actionsDisposable.dispose()
    }, removeAfterDisappear: false, hasDone: false, identifier: "proxy")

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
}


private func impulseProxyEnsureSelection(
    _ state: inout ImpulseProxy.ImpulseProxyState
) {
    let servers: [ImpulseProxy.ImpulseProxyState.Server] = impulseProxyAllServers(state)
    if let selected: String = state.selectedId, servers.contains(where: { (server: ImpulseProxy.ImpulseProxyState.Server) -> Bool in
        return server.id == selected
    }) {
        return
    }
    state.selectedId = servers.first?.id
}


private func impulseProxyStatusText(
    settings: ImpulseProxy.ImpulseProxyState,
    controller: ProxyController?,
    connection: ConnectionStatus
) -> String {
    if !settings.enabled {
        return strings().proxySettingsDisabled
    }
    guard let controller: ProxyController = controller else {
        return strings().connectionStatusConnectingToProxy
    }
    if controller.status == .failed {
        return "Failed: " + (controller.lastError ?? "unknown")
    }
    if controller.route == .blocked {
        return impulseProxyBlockedText
    }
    if controller.status == .running {
        switch connection {
        case .online, .updating:
            return strings().proxySettingsItemConnected
        default:
            return strings().connectingStatusConnecting
        }
    }
    return strings().connectionStatusConnectingToProxy
}


private func impulseProxyListEntries(
    state: ImpulseProxyListState,
    statusText: String,
    showUseCalls: Bool,
    hasAdvanced: Bool,
    arguments: ImpulseProxyListArguments
) -> [InputDataEntry] {
    let settings: ImpulseProxy.ImpulseProxyState = state.settings
    let servers: [ImpulseProxy.ImpulseProxyState.Server] = impulseProxyAllServers(settings)
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    impulseProxySectionBreak(entries: &entries, sectionId: &sectionId)

    if state.migrationNoticePending {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(impulseProxyMigrationText), data: InputDataGeneralTextData(viewType: .textTopItem)))
        index += 1
    }

    var powerSpecs: [ImpulseProxyRowSpec] = []
    powerSpecs.append(ImpulseProxyRowSpec(identifier: "proxy.enable", title: strings().proxySettingsEnable, detail: nil, type: .switchable(settings.enabled), isEnabled: settings.enabled || !servers.isEmpty, isAction: false, action: arguments.toggleEnabled, menuItems: nil))
    impulseProxyAppendRows(entries: &entries, specs: powerSpecs, sectionId: sectionId, index: &index)
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(statusText), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1

    impulseProxySectionBreak(entries: &entries, sectionId: &sectionId)

    var toggleSpecs: [ImpulseProxyRowSpec] = []
    toggleSpecs.append(ImpulseProxyRowSpec(identifier: "proxy.transport", title: impulseProxyTransportText, detail: nil, type: .switchable(settings.useForTransport), isEnabled: !(settings.useForTransport && !settings.useForCalls), isAction: false, action: arguments.toggleTransport, menuItems: nil))
    if showUseCalls && impulseProxyCallsToggleVisible {
        toggleSpecs.append(ImpulseProxyRowSpec(identifier: "proxy.calls", title: strings().proxySettingsUseForCalls, detail: nil, type: .switchable(settings.useForCalls), isEnabled: !(settings.useForCalls && !settings.useForTransport), isAction: false, action: arguments.toggleCalls, menuItems: nil))
    }
    impulseProxyAppendRows(entries: &entries, specs: toggleSpecs, sectionId: sectionId, index: &index)

    impulseProxySectionBreak(entries: &entries, sectionId: &sectionId)

    var serverSpecs: [ImpulseProxyRowSpec] = []
    serverSpecs.append(ImpulseProxyRowSpec(identifier: "proxy.add", title: strings().proxySettingsAddProxy, detail: nil, type: .none, isEnabled: true, isAction: true, action: arguments.addServer, menuItems: nil))
    for server: ImpulseProxy.ImpulseProxyState.Server in settings.manual {
        serverSpecs.append(impulseProxyServerSpec(server: server, identifier: "proxy.manual.\(server.id)", settings: settings, arguments: arguments, deletable: true))
    }
    for subscription: ImpulseProxy.ImpulseProxyState.Subscription in settings.subscriptions {
        serverSpecs.append(impulseProxySubscriptionSpec(subscription: subscription, arguments: arguments))
        for server: ImpulseProxy.ImpulseProxyState.Server in subscription.servers {
            serverSpecs.append(impulseProxyServerSpec(server: server, identifier: "proxy.subscription.\(subscription.id).\(server.id)", settings: settings, arguments: arguments, deletable: false))
        }
    }
    impulseProxyAppendRows(entries: &entries, specs: serverSpecs, sectionId: sectionId, index: &index)

    if hasAdvanced {
        impulseProxySectionBreak(entries: &entries, sectionId: &sectionId)
        var advancedSpecs: [ImpulseProxyRowSpec] = []
        advancedSpecs.append(ImpulseProxyRowSpec(identifier: "proxy.advanced", title: impulseProxyAdvancedText, detail: nil, type: .next, isEnabled: true, isAction: false, action: arguments.openAdvanced, menuItems: nil))
        impulseProxyAppendRows(entries: &entries, specs: advancedSpecs, sectionId: sectionId, index: &index)
    }

    impulseProxySectionBreak(entries: &entries, sectionId: &sectionId)

    return entries
}


private func impulseProxySectionBreak(
    entries: inout [InputDataEntry],
    sectionId: inout Int32
) {
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
}


private func impulseProxyAppendRows(
    entries: inout [InputDataEntry],
    specs: [ImpulseProxyRowSpec],
    sectionId: Int32,
    index: inout Int32
) {
    for position: Int in 0 ..< specs.count {
        let spec: ImpulseProxyRowSpec = specs[position]
        let viewType: GeneralViewType = impulseProxyViewType(position: position, count: specs.count)
        let key: ImpulseProxyRowKey = ImpulseProxyRowKey(title: spec.title, detail: spec.detail, type: spec.type, isEnabled: spec.isEnabled, isAction: spec.isAction, viewType: viewType)
        entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier(spec.identifier), equatable: InputDataEquatable(key), comparable: nil, item: { (initialSize: NSSize, stableId: InputDataEntryId) -> TableRowItem in
            return impulseProxyRowItem(initialSize: initialSize, stableId: stableId, key: key, action: spec.action, menuItems: spec.menuItems)
        }))
        index += 1
    }
}


private func impulseProxyRowItem(
    initialSize: NSSize,
    stableId: InputDataEntryId,
    key: ImpulseProxyRowKey,
    action: @escaping () -> Void,
    menuItems: (() -> [ContextMenuItem])?
) -> TableRowItem {
    if key.isAction {
        return GeneralInteractedRowItem(initialSize, stableId: stableId, name: key.title, nameStyle: blueActionButton, type: key.type, viewType: key.viewType, action: action, thumb: GeneralThumbAdditional(thumb: theme.icons.proxyAddProxy, textInset: 30, thumbInset: -5), inset: NSEdgeInsets(left: 20, right: 20), enabled: key.isEnabled)
    }
    return GeneralInteractedRowItem(initialSize, stableId: stableId, name: key.title, description: key.detail, type: key.type, viewType: key.viewType, action: action, enabled: key.isEnabled, menuItems: menuItems)
}


private func impulseProxyViewType(
    position: Int,
    count: Int
) -> GeneralViewType {
    if count <= 1 {
        return .singleItem
    }
    if position == 0 {
        return .firstItem
    }
    if position == count - 1 {
        return .lastItem
    }
    return .innerItem
}


private func impulseProxyServerSpec(
    server: ImpulseProxy.ImpulseProxyState.Server,
    identifier: String,
    settings: ImpulseProxy.ImpulseProxyState,
    arguments: ImpulseProxyListArguments,
    deletable: Bool
) -> ImpulseProxyRowSpec {
    let serverId: String = server.id
    var menuItems: (() -> [ContextMenuItem])? = nil
    if deletable {
        menuItems = { () -> [ContextMenuItem] in
            return [
                ContextMenuItem(impulseProxyDeleteText, handler: {
                    arguments.deleteManual(serverId)
                })
            ]
        }
    }
    let isSelected: Bool = settings.selectedId == serverId
    return ImpulseProxyRowSpec(identifier: identifier, title: server.name, detail: "\(server.host):\(server.port), \(server.network), \(server.security)", type: .selectable(isSelected), isEnabled: true, isAction: false, action: {
        arguments.selectServer(serverId)
    }, menuItems: menuItems)
}


private func impulseProxySubscriptionSpec(
    subscription: ImpulseProxy.ImpulseProxyState.Subscription,
    arguments: ImpulseProxyListArguments
) -> ImpulseProxyRowSpec {
    let title: String = subscription.meta.title ?? (URL(string: subscription.url)?.host ?? subscription.id)
    var detail: String = "\(subscription.servers.count) servers"
    if let error: String = subscription.lastError {
        detail += ", " + error
    }
    let menuItems: () -> [ContextMenuItem] = { () -> [ContextMenuItem] in
        return [
            ContextMenuItem(impulseProxyUpdateText, handler: {
                arguments.refreshSubscription(subscription)
            }),
            ContextMenuItem(impulseProxyDeleteText, handler: {
                arguments.deleteSubscription(subscription.id)
            })
        ]
    }
    return ImpulseProxyRowSpec(identifier: "proxy.subscription.\(subscription.id)", title: title, detail: detail, type: .none, isEnabled: true, isAction: false, action: {}, menuItems: menuItems)
}
