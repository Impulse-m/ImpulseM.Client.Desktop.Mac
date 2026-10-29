import Foundation
import ImpulseProxy
import ImpulseTransport
import Postbox
import SwiftSignalKit
import TelegramCore


/// Writes one state to the stored record. It calls `completed` once the write has finished, and returns the
/// disposable of the write, which the runtime releases when `completed` runs.
typealias ImpulseProxyRecordWriter = (ImpulseProxy.ImpulseProxyState, @escaping () -> Void) -> Disposable


/// The single owner of the ImpulseM proxy controller and of the route the transport uses.
///
/// The app starts it once at launch and stops it at termination. Until it starts, the route is BLOCKED (the blackhole),
/// never direct. The controller is created from the stored record, and every later change of the record is applied to it.
/// A change made through the controller is written back to the record, and the write does not restart the core again.
/// `stop()` ends the record observer, so a record change made after the stop is not applied and cannot restart the core.
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
    private var started: Bool = false
    private var stopped: Bool = false
    private var controllerValue: ProxyController?
    private var adapterValue: ImpulseProxyRouteAdapter?
    private var routeObservation: ImpulseProxyRouteObservation?
    private var recordDisposable: Disposable?
    private var recordWriter: ImpulseProxyRecordWriter?
    // The last state known to be in the stored record, either read from it or written to it.
    private var lastRecord: ImpulseProxy.ImpulseProxyState?
    // Writes sent to the record that have not completed yet, oldest first.
    private var inFlightWrites: [ImpulseProxyRuntimeWrite] = []
    private var writeSequence: Int = 0
    private var writeDisposables: [Int: Disposable] = [:]
    private var subscriptionSessionValue: ImpulseProxySubscriptionSession?
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


    /// The number of writes sent to the record that have not completed yet.
    var inFlightWriteCount: Int {
        return locked { () -> Int in
            return inFlightWrites.count
        }
    }


    /// The number of write disposables the runtime still holds. A completed write releases its disposable.
    var retainedWriteCount: Int {
        return locked { () -> Int in
            return writeDisposables.count
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


    /// The stored settings, as the runtime last applied them.
    public func settingsSignal() -> Signal<ImpulseProxy.ImpulseProxyState, NoError> {
        return settingsPromise.get()
    }


    /// The session that routes subscription downloads through the current route. The runtime owns it: the same session
    /// is returned while the route stays the same, and a route change invalidates it and builds the next one.
    /// The caller must not invalidate it.
    public func subscriptionSession() -> URLSession {
        let route: ImpulseProxyRoute? = currentRoute
        return locked { () -> URLSession in
            if let current: ImpulseProxySubscriptionSession = subscriptionSessionValue, current.route == route {
                return current.session
            }
            let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
            configuration.connectionProxyDictionary = ImpulseProxyConnectionProxy.dictionary(for: route)
            let session: URLSession = URLSession(configuration: configuration)
            // Tasks already running on the old session finish on it.
            subscriptionSessionValue?.session.finishTasksAndInvalidate()
            subscriptionSessionValue = ImpulseProxySubscriptionSession(
                route: route,
                session: session
            )
            return session
        }
    }


    /// Starts the runtime from the stored record. Later calls do nothing.
    public func start(
        accountManager: AccountManager<TelegramAccountManagerTypes>
    ) {
        start(
            recordSignal: ImpulseProxySettingsStore.signal(accountManager: accountManager),
            writeRecord: { (state: ImpulseProxy.ImpulseProxyState, completed: @escaping () -> Void) -> Disposable in
                return ImpulseProxySettingsStore.save(
                    accountManager: accountManager,
                    state: state
                ).start(completed: completed)
            }
        )
    }


    /// Stops the runtime at termination. It ends the record observer, so nothing applies a record change afterwards,
    /// and it stops the core. The controller stays, so a later record change cannot start the core again.
    public func stop() {
        let stopping: (controller: ProxyController?, observer: Disposable?) = locked { () -> (controller: ProxyController?, observer: Disposable?) in
            stopped = true
            let observer: Disposable? = recordDisposable
            recordDisposable = nil
            return (controller: controllerValue, observer: observer)
        }
        stopping.observer?.dispose()
        try? stopping.controller?.stopCore()
    }


    /// Starts the runtime from a record signal and a record writer. Later calls do nothing.
    func start(
        recordSignal: Signal<ImpulseProxy.ImpulseProxyState, NoError>,
        writeRecord: @escaping ImpulseProxyRecordWriter
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
        let disposeNow: Bool = locked { () -> Bool in
            if stopped {
                return true
            }
            recordDisposable = disposable
            return false
        }
        if disposeNow {
            disposable.dispose()
        }
    }


    // Creates the controller from the first record. A later record is applied unless it is older than a write in flight:
    // while a write is in flight, only the newest write's own echo is applied, and a record that differs from it is ignored.
    private func applyRecord(
        _ record: ImpulseProxy.ImpulseProxyState
    ) {
        let accepted: Bool = locked { () -> Bool in
            if stopped {
                return false
            }
            if let newest: ImpulseProxyRuntimeWrite = inFlightWrites.last, newest.state != record {
                return false
            }
            lastRecord = record
            return true
        }
        if !accepted {
            return
        }
        settingsPromise.set(record)
        let existing: ProxyController? = locked { () -> ProxyController? in
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
        let pending: (sequence: Int, writer: ImpulseProxyRecordWriter)? = locked { () -> (sequence: Int, writer: ImpulseProxyRecordWriter)? in
            if lastRecord == state {
                return nil
            }
            guard let writer: ImpulseProxyRecordWriter = recordWriter else {
                return nil
            }
            lastRecord = state
            writeSequence += 1
            inFlightWrites.append(
                ImpulseProxyRuntimeWrite(
                    sequence: writeSequence,
                    state: state
                )
            )
            return (sequence: writeSequence, writer: writer)
        }
        guard let pending: (sequence: Int, writer: ImpulseProxyRecordWriter) = pending else {
            return
        }
        let sequence: Int = pending.sequence
        let disposable: Disposable = pending.writer(state, { [weak self] () -> Void in
            self?.finishWrite(sequence: sequence)
        })
        locked { () -> Void in
            // A write that completed before the writer returned has nothing left to hold.
            if inFlightWrites.contains(where: { (write: ImpulseProxyRuntimeWrite) -> Bool in
                return write.sequence == sequence
            }) {
                writeDisposables[sequence] = disposable
            }
        }
    }


    // Releases a completed write: it leaves the in-flight list and its disposable is dropped.
    private func finishWrite(
        sequence: Int
    ) {
        locked { () -> Void in
            inFlightWrites.removeAll { (write: ImpulseProxyRuntimeWrite) -> Bool in
                return write.sequence == sequence
            }
            writeDisposables.removeValue(forKey: sequence)
        }
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


private struct ImpulseProxyRuntimeWrite {
    let sequence: Int
    let state: ImpulseProxy.ImpulseProxyState
}


private struct ImpulseProxySubscriptionSession {
    let route: ImpulseProxyRoute?
    let session: URLSession
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
