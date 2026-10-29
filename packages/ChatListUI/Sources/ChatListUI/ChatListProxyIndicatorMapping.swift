import TelegramCore


public enum ChatListProxyRuntimeStatus: Equatable {
    case off
    case starting
    case running
    case failed
}


public enum ChatListProxyIndicatorMapping {
    /// Maps the proxy runtime status, the presence of a server and the connection status to the chat-list indicator.
    /// Returns nil when the indicator is hidden.
    public static func indicator(
        isFeatureEnabled: Bool,
        hasServer: Bool,
        runtime: ChatListProxyRuntimeStatus,
        connection: ConnectionStatus
    ) -> ChatListProxyIndicator? {
        guard isFeatureEnabled else {
            return nil
        }
        guard hasServer else {
            return nil
        }
        switch runtime {
        case .off:
            return .off

        case .starting:
            return .connecting

        case .failed:
            return .failed

        case .running:
            switch connection {
            case .online, .updating:
                return .connected

            case .connecting, .waitingForNetwork:
                return .connecting
            }
        }
    }
}
