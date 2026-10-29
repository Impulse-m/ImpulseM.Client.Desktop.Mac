import XCTest
import ImpulseProxy
import ImpulseTransport
@testable import ProxyUI


/// Scripted libXray driver for the route tests. `run` marks the core as running and `stop` clears it, with no native call.
final class RouteFakeXrayCoreDriver: XrayCoreDriver, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var runningValue: Bool = false


    func isRunning() throws -> Bool {
        return locked { () -> Bool in
            return runningValue
        }
    }


    func stop() throws {
        locked { () -> Void in
            runningValue = false
        }
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
        locked { () -> Void in
            runningValue = true
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
}


/// Collects the epochs delivered to a route observer. Safe to call from any thread.
final class RouteEpochRecorder: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var epochs: [Int] = []


    var values: [Int] {
        return locked { () -> [Int] in
            return epochs
        }
    }


    func append(
        _ epoch: Int
    ) {
        locked { () -> Void in
            epochs.append(epoch)
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
}


final class ImpulseProxyRouteAdapterTests: XCTestCase {
    private static let validOutbound: String = #"{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"h.example","port":443,"users":[{"id":"11111111-1111-1111-1111-111111111111","encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"a"}}}"#


    private static let blackholeRoute: ImpulseProxyRoute = ImpulseProxyRoute(
        host: "127.0.0.1",
        port: 9,
        username: nil,
        password: nil
    )


    func testBlockedRouteIsBlackholeWithoutCredentials() {
        let controller: ProxyController = ImpulseProxyRouteAdapterTests.makeController(
            state: ImpulseProxyState(enabled: true),
            driver: RouteFakeXrayCoreDriver()
        )
        let adapter: ImpulseProxyRouteAdapter = ImpulseProxyRouteAdapter(controller: controller)

        XCTAssertEqual(controller.route, .blocked)
        XCTAssertEqual(adapter.currentRoute, ImpulseProxyRouteAdapterTests.blackholeRoute)
    }


    func testDirectRouteGivesNil() {
        let controller: ProxyController = ImpulseProxyRouteAdapterTests.makeController(
            state: ImpulseProxyState(enabled: false),
            driver: RouteFakeXrayCoreDriver()
        )
        let adapter: ImpulseProxyRouteAdapter = ImpulseProxyRouteAdapter(controller: controller)

        XCTAssertEqual(controller.route, .direct)
        XCTAssertNil(adapter.currentRoute)
    }


    func testTransportToggleOffGivesDirectRouteNil() {
        let controller: ProxyController = ImpulseProxyRouteAdapterTests.makeController(
            state: ImpulseProxyState(
                enabled: true,
                useForTransport: false,
                useForCalls: true
            ),
            driver: RouteFakeXrayCoreDriver()
        )
        let adapter: ImpulseProxyRouteAdapter = ImpulseProxyRouteAdapter(controller: controller)

        XCTAssertEqual(controller.route, .direct)
        XCTAssertNil(adapter.currentRoute)
    }


    func testRunningRouteGivesRuntimeEndpointAndCredentials() throws {
        let server: ImpulseProxyState.Server = ImpulseProxyState.Server(
            id: "a",
            name: "A",
            host: "h.example",
            port: 443,
            network: "tcp",
            security: "tls",
            outboundJson: ImpulseProxyRouteAdapterTests.validOutbound
        )
        let controller: ProxyController = ImpulseProxyRouteAdapterTests.makeController(
            state: ImpulseProxyState(
                enabled: true,
                selectedId: "a",
                manual: [server]
            ),
            driver: RouteFakeXrayCoreDriver()
        )
        let adapter: ImpulseProxyRouteAdapter = ImpulseProxyRouteAdapter(controller: controller)

        controller.restartCore()
        XCTAssertEqual(controller.status, .running)

        let access: ProxyAccess = try XCTUnwrap(controller.runtime?.httpAccess)
        let expected: ImpulseProxyRoute = ImpulseProxyRoute(
            host: access.endpoint.host,
            port: access.endpoint.port,
            username: access.credentials.user,
            password: access.credentials.password
        )

        XCTAssertEqual(adapter.currentRoute, expected)
        XCTAssertEqual(expected.host, "127.0.0.1")
        XCTAssertEqual(expected.port, 41001)
        XCTAssertFalse(expected.username?.isEmpty ?? true)
        XCTAssertFalse(expected.password?.isEmpty ?? true)
    }


    func testObservationDeliversEpochChangesUntilCancelled() {
        let controller: ProxyController = ImpulseProxyRouteAdapterTests.makeController(
            state: ImpulseProxyState(enabled: false),
            driver: RouteFakeXrayCoreDriver()
        )
        let adapter: ImpulseProxyRouteAdapter = ImpulseProxyRouteAdapter(controller: controller)
        let recorder: RouteEpochRecorder = RouteEpochRecorder()
        let observation: ImpulseProxyRouteObservation = adapter.observe { (epoch: Int) -> Void in
            recorder.append(epoch)
        }

        controller.update { (state: inout ImpulseProxyState) -> Void in
            state.enabled = true
        }
        controller.restartCore()
        let deliveredBeforeCancel: [Int] = recorder.values
        XCTAssertFalse(deliveredBeforeCancel.isEmpty)

        observation.cancel()
        controller.update { (state: inout ImpulseProxyState) -> Void in
            state.enabled = false
        }
        controller.restartCore()

        XCTAssertNil(adapter.currentRoute)
        XCTAssertEqual(recorder.values, deliveredBeforeCancel)
    }


    private static func makeController(
        state: ImpulseProxyState,
        driver: XrayCoreDriver
    ) -> ProxyController {
        return ProxyController(
            initialState: state,
            driver: driver,
            persist: { (_: ImpulseProxyState) -> Void in
            },
            scheduler: { (_: Double, _: @escaping @Sendable () -> Void) -> Void in
            }
        )
    }
}
