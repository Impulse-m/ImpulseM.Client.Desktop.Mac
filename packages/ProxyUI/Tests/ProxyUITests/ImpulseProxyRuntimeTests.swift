import XCTest
import ImpulseProxy
import ImpulseTransport
import SwiftSignalKit
@testable import ProxyUI


/// Records what one test saw: the factory calls, the core runs, the record writes and the route deliveries.
/// Safe to call from any thread.
final class ImpulseProxyRuntimeProbe: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var factoryCallValue: Int = 0
    private var runValue: Int = 0
    private var writeValue: Int = 0
    private var runCallback: ((Int) -> Void)?


    var factoryCallCount: Int {
        return locked { () -> Int in
            return factoryCallValue
        }
    }


    var runCount: Int {
        return locked { () -> Int in
            return runValue
        }
    }


    var writeCount: Int {
        return locked { () -> Int in
            return writeValue
        }
    }


    func setRunCallback(
        _ callback: @escaping (Int) -> Void
    ) {
        locked { () -> Void in
            runCallback = callback
        }
    }


    func recordFactoryCall() {
        locked { () -> Void in
            factoryCallValue += 1
        }
    }


    func recordWrite() {
        locked { () -> Void in
            writeValue += 1
        }
    }


    func recordRun() {
        let result: (Int, ((Int) -> Void)?) = locked { () -> (Int, ((Int) -> Void)?) in
            runValue += 1
            return (runValue, runCallback)
        }
        result.1?(result.0)
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
}


/// Counts the route deliveries of one test. Safe to call from any thread.
final class ImpulseProxyRuntimeCounter: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var countValue: Int = 0


    var value: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return countValue
    }


    func increment() {
        lock.lock()
        countValue += 1
        lock.unlock()
    }
}


/// Scripted libXray driver. `run` marks the core as running, `stop` clears it, and every run is reported to the probe.
final class ImpulseProxyRuntimeFakeDriver: XrayCoreDriver, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private let probe: ImpulseProxyRuntimeProbe
    private var runningValue: Bool = false


    init(
        probe: ImpulseProxyRuntimeProbe
    ) {
        self.probe = probe
    }


    func isRunning() throws -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return runningValue
    }


    func stop() throws {
        lock.lock()
        runningValue = false
        lock.unlock()
    }


    func freePorts(
        count: Int
    ) throws -> [Int] {
        return [41001, 41002]
    }


    func test(
        configJSON: String
    ) throws {
    }


    func run(
        configJSON: String
    ) throws {
        lock.lock()
        runningValue = true
        lock.unlock()
        probe.recordRun()
    }
}


final class ImpulseProxyRuntimeTests: XCTestCase {
    private static let validOutbound: String = #"{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"h.example","port":443,"users":[{"id":"11111111-1111-1111-1111-111111111111","encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"a"}}}"#


    private static let blackholeRoute: ImpulseProxyRoute = ImpulseProxyRoute(
        host: "127.0.0.1",
        port: 9,
        username: nil,
        password: nil
    )


    func testStartTwiceCreatesOneController() {
        let probe: ImpulseProxyRuntimeProbe = ImpulseProxyRuntimeProbe()
        let runtime: ImpulseProxyRuntime = ImpulseProxyRuntimeTests.makeRuntime(probe: probe)
        let record: ValuePromise<ImpulseProxyState> = ValuePromise<ImpulseProxyState>(
            ImpulseProxyState(enabled: false),
            ignoreRepeated: true
        )

        runtime.start(
            recordSignal: record.get(),
            writeRecord: ImpulseProxyRuntimeTests.makeWriter(record: record, probe: probe)
        )
        let first: ProxyController? = runtime.controller
        runtime.start(
            recordSignal: record.get(),
            writeRecord: ImpulseProxyRuntimeTests.makeWriter(record: record, probe: probe)
        )

        XCTAssertNotNil(first)
        XCTAssertTrue(first === runtime.controller)
        XCTAssertEqual(probe.factoryCallCount, 1)
    }


    func testRouteIsBlockedBeforeStart() {
        let probe: ImpulseProxyRuntimeProbe = ImpulseProxyRuntimeProbe()
        let runtime: ImpulseProxyRuntime = ImpulseProxyRuntimeTests.makeRuntime(probe: probe)

        XCTAssertNil(runtime.controller)
        XCTAssertEqual(runtime.currentRoute, ImpulseProxyRuntimeTests.blackholeRoute)
        XCTAssertEqual(probe.factoryCallCount, 0)
    }


    func testStatusIsOffBeforeStartAndRunningAfterStart() {
        let probe: ImpulseProxyRuntimeProbe = ImpulseProxyRuntimeProbe()
        let runtime: ImpulseProxyRuntime = ImpulseProxyRuntimeTests.makeRuntime(probe: probe)
        let record: ValuePromise<ImpulseProxyState> = ValuePromise<ImpulseProxyState>(
            ImpulseProxyState(
                enabled: true,
                selectedId: "a",
                manual: [ImpulseProxyRuntimeTests.makeServer(id: "a")]
            ),
            ignoreRepeated: true
        )
        var statusBeforeStart: ProxyStatus?
        let offDisposable: Disposable = runtime.statusSignal().start(next: { (status: ProxyStatus) -> Void in
            statusBeforeStart = status
        })
        offDisposable.dispose()
        XCTAssertEqual(statusBeforeStart, ProxyStatus.off)

        let running: XCTestExpectation = expectation(description: "core running")
        let runningDisposable: Disposable = runtime.statusSignal().start(next: { (status: ProxyStatus) -> Void in
            if status == .running {
                running.fulfill()
            }
        })
        runtime.start(
            recordSignal: record.get(),
            writeRecord: ImpulseProxyRuntimeTests.makeWriter(record: record, probe: probe)
        )
        wait(for: [running], timeout: 5.0)
        runningDisposable.dispose()

        XCTAssertEqual(runtime.controller?.status, ProxyStatus.running)
    }


    func testExternalRecordChangeIsAppliedWithoutWritingBack() throws {
        let probe: ImpulseProxyRuntimeProbe = ImpulseProxyRuntimeProbe()
        let runtime: ImpulseProxyRuntime = ImpulseProxyRuntimeTests.makeRuntime(probe: probe)
        let record: ValuePromise<ImpulseProxyState> = ValuePromise<ImpulseProxyState>(
            ImpulseProxyState(
                enabled: true,
                selectedId: "a",
                manual: [
                    ImpulseProxyRuntimeTests.makeServer(id: "a"),
                    ImpulseProxyRuntimeTests.makeServer(id: "b")
                ]
            ),
            ignoreRepeated: true
        )
        let firstRun: XCTestExpectation = expectation(description: "first core run")
        let secondRun: XCTestExpectation = expectation(description: "second core run")
        probe.setRunCallback { (runNumber: Int) -> Void in
            if runNumber == 1 {
                firstRun.fulfill()
            }
            if runNumber == 2 {
                secondRun.fulfill()
            }
        }
        runtime.start(
            recordSignal: record.get(),
            writeRecord: ImpulseProxyRuntimeTests.makeWriter(record: record, probe: probe)
        )
        wait(for: [firstRun], timeout: 5.0)

        let changed: ImpulseProxyState = ImpulseProxyState(
            enabled: true,
            selectedId: "b",
            manual: [
                ImpulseProxyRuntimeTests.makeServer(id: "a"),
                ImpulseProxyRuntimeTests.makeServer(id: "b")
            ]
        )
        record.set(changed)
        wait(for: [secondRun], timeout: 5.0)

        let controller: ProxyController = try XCTUnwrap(runtime.controller)
        try? controller.stopCore()
        XCTAssertEqual(controller.snapshot.selectedId, "b")
        XCTAssertEqual(probe.runCount, 2)
        XCTAssertEqual(probe.writeCount, 0)
    }


    func testOwnControllerChangeIsWrittenOnceAndDoesNotRestartTwice() throws {
        let probe: ImpulseProxyRuntimeProbe = ImpulseProxyRuntimeProbe()
        let runtime: ImpulseProxyRuntime = ImpulseProxyRuntimeTests.makeRuntime(probe: probe)
        let record: ValuePromise<ImpulseProxyState> = ValuePromise<ImpulseProxyState>(
            ImpulseProxyState(
                enabled: true,
                selectedId: "a",
                manual: [
                    ImpulseProxyRuntimeTests.makeServer(id: "a"),
                    ImpulseProxyRuntimeTests.makeServer(id: "b")
                ]
            ),
            ignoreRepeated: true
        )
        let firstRun: XCTestExpectation = expectation(description: "first core run")
        let secondRun: XCTestExpectation = expectation(description: "second core run")
        probe.setRunCallback { (runNumber: Int) -> Void in
            if runNumber == 1 {
                firstRun.fulfill()
            }
            if runNumber == 2 {
                secondRun.fulfill()
            }
        }
        runtime.start(
            recordSignal: record.get(),
            writeRecord: ImpulseProxyRuntimeTests.makeWriter(record: record, probe: probe)
        )
        wait(for: [firstRun], timeout: 5.0)

        let controller: ProxyController = try XCTUnwrap(runtime.controller)
        controller.update { (state: inout ImpulseProxyState) -> Void in
            state.selectedId = "b"
        }
        wait(for: [secondRun], timeout: 5.0)
        try? controller.stopCore()

        XCTAssertEqual(probe.writeCount, 1)
        XCTAssertEqual(probe.runCount, 2)
        XCTAssertEqual(controller.snapshot.selectedId, "b")
    }


    func testRouteObserverGetsEpochOnStartAndStopsAfterCancel() throws {
        let probe: ImpulseProxyRuntimeProbe = ImpulseProxyRuntimeProbe()
        let runtime: ImpulseProxyRuntime = ImpulseProxyRuntimeTests.makeRuntime(probe: probe)
        let counter: ImpulseProxyRuntimeCounter = ImpulseProxyRuntimeCounter()
        let observation: ImpulseProxyRouteObservation = runtime.observe { (_: Int) -> Void in
            counter.increment()
        }
        let record: ValuePromise<ImpulseProxyState> = ValuePromise<ImpulseProxyState>(
            ImpulseProxyState(enabled: false),
            ignoreRepeated: true
        )

        runtime.start(
            recordSignal: record.get(),
            writeRecord: ImpulseProxyRuntimeTests.makeWriter(record: record, probe: probe)
        )
        XCTAssertEqual(counter.value, 1)

        observation.cancel()
        let controller: ProxyController = try XCTUnwrap(runtime.controller)
        controller.update { (state: inout ImpulseProxyState) -> Void in
            state.enabled = true
            state.selectedId = "a"
            state.manual = [ImpulseProxyRuntimeTests.makeServer(id: "a")]
        }
        try? controller.stopCore()

        XCTAssertEqual(counter.value, 1)
    }


    func testStopLeavesCoreNotRunningAndRouteBlocked() throws {
        let probe: ImpulseProxyRuntimeProbe = ImpulseProxyRuntimeProbe()
        let runtime: ImpulseProxyRuntime = ImpulseProxyRuntimeTests.makeRuntime(probe: probe)
        let record: ValuePromise<ImpulseProxyState> = ValuePromise<ImpulseProxyState>(
            ImpulseProxyState(
                enabled: true,
                selectedId: "a",
                manual: [ImpulseProxyRuntimeTests.makeServer(id: "a")]
            ),
            ignoreRepeated: true
        )
        let running: XCTestExpectation = expectation(description: "core running")
        let runningDisposable: Disposable = runtime.statusSignal().start(next: { (status: ProxyStatus) -> Void in
            if status == .running {
                running.fulfill()
            }
        })
        runtime.start(
            recordSignal: record.get(),
            writeRecord: ImpulseProxyRuntimeTests.makeWriter(record: record, probe: probe)
        )
        wait(for: [running], timeout: 5.0)
        runningDisposable.dispose()

        runtime.stop()

        let controller: ProxyController = try XCTUnwrap(runtime.controller)
        XCTAssertNil(controller.runtime)
        XCTAssertNotEqual(controller.status, ProxyStatus.running)
        XCTAssertEqual(runtime.currentRoute, ImpulseProxyRuntimeTests.blackholeRoute)

        var latestStatus: ProxyStatus?
        let latestDisposable: Disposable = runtime.statusSignal().start(next: { (status: ProxyStatus) -> Void in
            latestStatus = status
        })
        latestDisposable.dispose()
        XCTAssertEqual(latestStatus, controller.status)
    }


    private static func makeRuntime(
        probe: ImpulseProxyRuntimeProbe
    ) -> ImpulseProxyRuntime {
        return ImpulseProxyRuntime(
            driverFactory: { () -> XrayCoreDriver in
                probe.recordFactoryCall()
                return ImpulseProxyRuntimeFakeDriver(probe: probe)
            },
            scheduler: { (_: Double, _: @escaping @Sendable () -> Void) -> Void in
            }
        )
    }


    private static func makeWriter(
        record: ValuePromise<ImpulseProxyState>,
        probe: ImpulseProxyRuntimeProbe
    ) -> (ImpulseProxyState) -> Void {
        return { (state: ImpulseProxyState) -> Void in
            probe.recordWrite()
            record.set(state)
        }
    }


    private static func makeServer(
        id: String
    ) -> ImpulseProxyState.Server {
        return ImpulseProxyState.Server(
            id: id,
            name: id.uppercased(),
            host: "h.example",
            port: 443,
            network: "tcp",
            security: "tls",
            outboundJson: ImpulseProxyRuntimeTests.validOutbound
        )
    }
}
