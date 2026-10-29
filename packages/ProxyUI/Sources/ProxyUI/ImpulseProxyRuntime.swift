import Foundation
import ImpulseProxy
import ImpulseTransport
import Postbox
import SwiftSignalKit
import TelegramCore


/// The single owner of the ImpulseM proxy controller and of the route the transport uses.
///
/// The app starts it once at launch and stops it at termination. Until it starts, the route is BLOCKED (the blackhole),
/// never direct. The controller is created from the stored record, and every later change of the record is applied to it.
/// A change made through the controller is written back to the record, and the write does not restart the core again.
public final class ImpulseProxyRuntime: ImpulseProxyRouteSource, @unchecked Sendable {
    /// The process-wide runtime. The app starts it from `launchApp` and stops it in `applicationWillTerminate`.
    public static let shared: ImpulseProxyRuntime = ImpulseProxyRuntime(
        driverFactory: { () -> XrayCoreDriver in
            return LibXrayCoreDriver(
                client: LibXrayClient(
                    bridge: LibXrayCGoBridge()
                )
            )
        },
        scheduler: nil
    )

    private let lock: NSLock = NSLock()
    private let driverFactory: () -> XrayCoreDriver
    private let scheduler: ProxyController.Scheduler?
    private let statusPromise: ValuePromise<ProxyStatus> = ValuePromise<ProxyStatus>(ProxyStatus.off, ignoreRepeated: true)
    private let settingsPromise: ValuePromise<ImpulseProxy.ImpulseProxyState> = ValuePromise<ImpulseProxy.ImpulseProxyState>(
        ImpulseProxy.ImpulseProxyState(),
        ignoreRepeated: true
    )
    private let disposables: DisposableSet = DisposableSet()
    private var started: Bool = false
    private var controllerValue: ProxyController?
    private var adapterValue: ImpulseProxyRouteAdapter?
    private var routeObservation: ImpulseProxyRouteObservation?
    private var recordWriter: ((ImpulseProxy.ImpulseProxyState) -> Void)?
    // The last state known to be in the stored record, either read from it or written to it.
    private var lastRecord: ImpulseProxy.ImpulseProxyState?
    private var routeHandlers: [ImpulseProxyRuntimeRouteHandler] = []
    private var nextHandlerIdentifier: Int = 0


    init(
        driverFactory: @escaping () -> XrayCoreDriver,
        scheduler: ProxyController.Scheduler?
    ) {
        self.driverFactory = driverFactory
        self.scheduler = scheduler
    }


    /// The controller, or nil until the runtime has started.
    public var controller: ProxyController? {
        return locked { () -> ProxyController? in
            return controllerValue
        }
    }


    /// The route for a connection opened now. Before the start and while the controller is missing, it is the blackhole.
    public var currentRoute: ImpulseProxyRoute? {
        let adapter: ImpulseProxyRouteAdapter? = locked { () -> ImpulseProxyRouteAdapter? in
            return adapterValue
        }
        guard let adapter: ImpulseProxyRouteAdapter = adapter else {
            return ImpulseProxyRuntime.blackholeRoute
        }
        return adapter.currentRoute
    }


    /// Delivers the route epoch after each change of the route, and once after the runtime starts.
    public func observe(
        _ handler: @escaping @Sendable (Int) -> Void
    ) -> ImpulseProxyRouteObservation {
        let identifier: Int = locked { () -> Int in
            nextHandlerIdentifier += 1
            routeHandlers.append(
                ImpulseProxyRuntimeRouteHandler(
                    identifier: nextHandlerIdentifier,
                    handler: handler
                )
            )
            return nextHandlerIdentifier
        }
        return ImpulseProxyRuntimeRouteObservation(
            onCancel: { [weak self] () -> Void in
                self?.removeRouteHandler(identifier: identifier)
            }
        )
    }


    /// The core status. Before the start it is OFF.
    public func statusSignal() -> Signal<ProxyStatus, NoError> {
        return statusPromise.get()
    }


    /// The stored settings, as the runtime last saw them.
    public func settingsSignal() -> Signal<ImpulseProxy.ImpulseProxyState, NoError> {
        return settingsPromise.get()
    }


    /// A session that routes through the current route. The caller invalidates it when it is done.
    public func subscriptionSession() -> URLSession {
        let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ImpulseProxyConnectionProxy.dictionary(for: currentRoute)
        return URLSession(configuration: configuration)
    }


    /// Starts the runtime from the stored record. Later calls do nothing.
    public func start(
        accountManager: AccountManager<TelegramAccountManagerTypes>
    ) {
        start(
            recordSignal: ImpulseProxySettingsStore.signal(accountManager: accountManager),
            writeRecord: { (state: ImpulseProxy.ImpulseProxyState) -> Void in
                let disposable: Disposable = ImpulseProxySettingsStore.save(
                    accountManager: accountManager,
                    state: state
                ).start()
                self.disposables.add(disposable)
            }
        )
    }


    /// Stops the core at termination. The runtime keeps its controller, so nothing restarts the core afterwards.
    public func stop() {
        let current: ProxyController? = locked { () -> ProxyController? in
            return controllerValue
        }
        try? current?.stopCore()
    }


    /// Starts the runtime from a record signal and a record writer. Later calls do nothing.
    func start(
        recordSignal: Signal<ImpulseProxy.ImpulseProxyState, NoError>,
        writeRecord: @escaping (ImpulseProxy.ImpulseProxyState) -> Void
    ) {
        let shouldStart: Bool = locked { () -> Bool in
            if started {
                return false
            }
            started = true
            recordWriter = writeRecord
            return true
        }
        if !shouldStart {
            return
        }
        let disposable: Disposable = recordSignal.start(next: { [weak self] (record: ImpulseProxy.ImpulseProxyState) -> Void in
            self?.applyRecord(record)
        })
        disposables.add(disposable)
    }


    // Creates the controller from the first record, and applies each later record that differs from its snapshot.
    private func applyRecord(
        _ record: ImpulseProxy.ImpulseProxyState
    ) {
        settingsPromise.set(record)
        let existing: ProxyController? = locked { () -> ProxyController? in
            lastRecord = record
            return controllerValue
        }
        guard let controller: ProxyController = existing else {
            createController(record: record)
            return
        }
        if controller.snapshot != record {
            controller.update { (next: inout ImpulseProxy.ImpulseProxyState) -> Void in
                next = record
            }
        }
    }


    private func createController(
        record: ImpulseProxy.ImpulseProxyState
    ) {
        let controller: ProxyController = ProxyController(
            initialState: record,
            driver: driverFactory(),
            persist: { [weak self] (state: ImpulseProxy.ImpulseProxyState) -> Void in
                self?.persist(state)
            },
            scheduler: scheduler
        )
        let adapter: ImpulseProxyRouteAdapter = ImpulseProxyRouteAdapter(controller: controller)
        let observation: ImpulseProxyRouteObservation = adapter.observe { [weak self] (epoch: Int) -> Void in
            self?.relayRouteEpoch(epoch)
        }
        locked { () -> Void in
            controllerValue = controller
            adapterValue = adapter
            routeObservation = observation
        }
        controller.observeStatus { [weak self] (status: ProxyStatus) -> Void in
            self?.statusPromise.set(status)
        }
        statusPromise.set(controller.status)
        controller.startIfEnabled()
        relayRouteEpoch(controller.epoch)
    }


    // Writes the state to the record unless the record already holds it. The controller calls it on each update.
    private func persist(
        _ state: ImpulseProxy.ImpulseProxyState
    ) {
        let writer: ((ImpulseProxy.ImpulseProxyState) -> Void)? = locked { () -> ((ImpulseProxy.ImpulseProxyState) -> Void)? in
            if lastRecord == state {
                return nil
            }
            lastRecord = state
            return recordWriter
        }
        writer?(state)
    }


    private func relayRouteEpoch(
        _ epoch: Int
    ) {
        let handlers: [ImpulseProxyRuntimeRouteHandler] = locked { () -> [ImpulseProxyRuntimeRouteHandler] in
            return routeHandlers
        }
        for entry: ImpulseProxyRuntimeRouteHandler in handlers {
            // A subscription cancelled after the snapshot must not receive the epoch.
            let stillRegistered: Bool = locked { () -> Bool in
                return routeHandlers.contains { (current: ImpulseProxyRuntimeRouteHandler) -> Bool in
                    return current.identifier == entry.identifier
                }
            }
            if stillRegistered {
                entry.handler(epoch)
            }
        }
    }


    private func removeRouteHandler(
        identifier: Int
    ) {
        locked { () -> Void in
            routeHandlers.removeAll { (entry: ImpulseProxyRuntimeRouteHandler) -> Bool in
                return entry.identifier == identifier
            }
        }
    }


    private func locked<T>(
        _ body: () -> T
    ) -> T {
        lock.lock()
        defer {
            lock.unlock()
        }
        return body()
    }


    private static var blackholeRoute: ImpulseProxyRoute {
        return ImpulseProxyRoute(
            host: ProxySelector.blackholeEndpoint.host,
            port: ProxySelector.blackholeEndpoint.port,
            username: nil,
            password: nil
        )
    }


}


private struct ImpulseProxyRuntimeRouteHandler {
    let identifier: Int
    let handler: @Sendable (Int) -> Void
}


/// Removes a route handler of the runtime when it is cancelled. Safe to cancel more than once.
private final class ImpulseProxyRuntimeRouteObservation: ImpulseProxyRouteObservation {
    private let lock: NSLock = NSLock()
    private let onCancel: () -> Void
    private var active: Bool = true


    init(
        onCancel: @escaping () -> Void
    ) {
        self.onCancel = onCancel
    }


    func cancel() {
        lock.lock()
        let wasActive: Bool = active
        active = false
        lock.unlock()
        if wasActive {
            onCancel()
        }
    }
}
