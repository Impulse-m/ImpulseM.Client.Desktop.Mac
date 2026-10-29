import XCTest
import TelegramCore
@testable import ChatListUI


final class ChatListProxyIndicatorMappingTests: XCTestCase {
    private let connections: [ConnectionStatus] = [
        .waitingForNetwork,
        .connecting(proxyAddress: nil, proxyHasConnectionIssues: false),
        .updating(proxyAddress: nil),
        .online(proxyAddress: nil)
    ]


    private let runtimes: [ChatListProxyRuntimeStatus] = [
        .off,
        .starting,
        .running,
        .failed
    ]


    private func indicator(
        isFeatureEnabled: Bool,
        hasServer: Bool,
        runtime: ChatListProxyRuntimeStatus,
        connection: ConnectionStatus
    ) -> ChatListProxyIndicator? {
        return ChatListProxyIndicatorMapping.indicator(
            isFeatureEnabled: isFeatureEnabled,
            hasServer: hasServer,
            runtime: runtime,
            connection: connection
        )
    }


    func testFeatureDisabledHidesEveryState() {
        for runtime in runtimes {
            for connection in connections {
                let result: ChatListProxyIndicator? = indicator(
                    isFeatureEnabled: false,
                    hasServer: true,
                    runtime: runtime,
                    connection: connection
                )
                XCTAssertNil(result)
            }
        }
    }


    func testNoServerHidesEveryState() {
        for runtime in runtimes {
            for connection in connections {
                let result: ChatListProxyIndicator? = indicator(
                    isFeatureEnabled: true,
                    hasServer: false,
                    runtime: runtime,
                    connection: connection
                )
                XCTAssertNil(result)
            }
        }
    }


    func testRuntimeOffShowsOffWhateverTheConnection() {
        for connection in connections {
            let result: ChatListProxyIndicator? = indicator(
                isFeatureEnabled: true,
                hasServer: true,
                runtime: .off,
                connection: connection
            )
            XCTAssertEqual(result, .off)
        }
    }


    func testRuntimeStartingShowsConnectingWhateverTheConnection() {
        for connection in connections {
            let result: ChatListProxyIndicator? = indicator(
                isFeatureEnabled: true,
                hasServer: true,
                runtime: .starting,
                connection: connection
            )
            XCTAssertEqual(result, .connecting)
        }
    }


    func testRuntimeFailedShowsFailedWhateverTheConnection() {
        for connection in connections {
            let result: ChatListProxyIndicator? = indicator(
                isFeatureEnabled: true,
                hasServer: true,
                runtime: .failed,
                connection: connection
            )
            XCTAssertEqual(result, .failed)
        }
    }


    func testRunningWithOnlineOrUpdatingConnectionShowsConnected() {
        let connected: [ConnectionStatus] = [
            .online(proxyAddress: nil),
            .updating(proxyAddress: nil)
        ]
        for connection in connected {
            let result: ChatListProxyIndicator? = indicator(
                isFeatureEnabled: true,
                hasServer: true,
                runtime: .running,
                connection: connection
            )
            XCTAssertEqual(result, .connected)
        }
    }


    func testRunningWithConnectingOrWaitingConnectionShowsConnecting() {
        let pending: [ConnectionStatus] = [
            .connecting(proxyAddress: nil, proxyHasConnectionIssues: false),
            .waitingForNetwork
        ]
        for connection in pending {
            let result: ChatListProxyIndicator? = indicator(
                isFeatureEnabled: true,
                hasServer: true,
                runtime: .running,
                connection: connection
            )
            XCTAssertEqual(result, .connecting)
        }
    }
}
