import Cocoa
import Foundation
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Postbox
import TGUIKit
import TelegramVoip
import Localization
import ColorPalette
import TelegramContext
import TelegramUtils
import AVFoundation
import TelegramMediaUtils
import SystemPermissions
import ProxyUtils






private let callLogsLimit = 20

public func callLogNameForId(id: Int64, account: Account) -> String? {
    let path = callLogsPath(account: account)
    let namePrefix = "\(id)_"

    if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: nil) {
        for url in enumerator {
            if let url = url as? URL {
                if url.lastPathComponent.hasPrefix(namePrefix) {
                    return url.lastPathComponent
                }
            }
        }
    }
    return nil
}

public func callLogsPath(account: Account) -> String {
    return account.basePath + "/calls"
}

private func cleanupCallLogs(account: Account) {
    let path = callLogsPath(account: account)
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: path, isDirectory: nil) {
        try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
    }

    var files: [(URL, Date)] = []
    if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: nil) {
        for url in enumerator {
            if let url = url as? URL, let date = (try? url.resourceValues(forKeys: Set([.contentModificationDateKey])))?.contentModificationDate {
                files.append((url, date))
            }
        }
    }
    for url in callLogsToRemove(files, limit: callLogsLimit) {
        try? fileManager.removeItem(at: url)
    }
}

func callLogsToRemove(_ files: [(URL, Date)], limit: Int) -> [URL] {
    guard files.count > limit else {
        return []
    }
    return files.sorted(by: { $0.1 < $1.1 }).prefix(files.count - limit).map { $0.0 }
}

public struct OngoingCallContextState: Equatable {
    public enum State {
        case initializing
        case connected
        case reconnecting
        case failed
    }

    public enum VideoState: Equatable {
        case notAvailable
        case inactive
        case active
        case paused
    }

    public enum RemoteVideoState: Equatable {
        case inactive
        case active
        case paused
    }

    public enum RemoteAudioState: Equatable {
        case active
        case muted
    }

    public enum RemoteBatteryLevel: Equatable {
        case normal
        case low
    }

    public let state: State
    public let videoState: VideoState
    public let remoteVideoState: RemoteVideoState
    public let remoteAudioState: RemoteAudioState
    public let remoteBatteryLevel: RemoteBatteryLevel
    public let remoteAspectRatio: Float
    public init(state: State, videoState: VideoState, remoteVideoState: RemoteVideoState, remoteAudioState: RemoteAudioState, remoteBatteryLevel: RemoteBatteryLevel, remoteAspectRatio: Float) {
        self.state = state
        self.videoState = videoState
        self.remoteVideoState = remoteVideoState
        self.remoteAudioState = remoteAudioState
        self.remoteBatteryLevel = remoteBatteryLevel
        self.remoteAspectRatio = remoteAspectRatio
    }
}


/// Owns the LiveKit call context of one call. The LiveKit call context is main-actor isolated, so every access runs in a main-actor task.
private final class LiveKitCallBridge: @unchecked Sendable {
    private var context: LiveKitCallContext?
    private var isStopped: Bool = false
    private let reportState: (LiveKitCallState) -> Void


    init(reportState: @escaping (LiveKitCallState) -> Void) {
        self.reportState = reportState
    }


    /// Creates and starts the call. A parameter or protocol error ends the call at once with a connection failure.
    @MainActor
    func start(
        callId: Int64,
        version: String,
        parameters: String,
        authKey: Data
    ) {
        guard !self.isStopped else {
            return
        }
        let created: LiveKitCallContext
        do {
            created = try LiveKitCallContext(
                callId: callId,
                versions: [version],
                parameters: parameters,
                authKey: authKey
            )
        } catch {
            self.reportState(.ended(.connectionFailed))
            return
        }
        created.onStateChanged = { [weak self] (state: LiveKitCallState) in
            self?.reportState(state)
        }
        self.context = created
        created.start()
    }


    @MainActor
    func stop() {
        self.isStopped = true
        self.context?.stop()
    }
}


public final class OngoingCallContext {
    public struct AuxiliaryServer {
        public enum Connection {
            case stun
            case turn(username: String, password: String)
        }

        public let host: String
        public let port: Int
        public let connection: Connection

        public init(
            host: String,
            port: Int,
            connection: Connection
            ) {
            self.host = host
            self.port = port
            self.connection = connection
        }
    }

    /// The highest call layer this client speaks on LiveKit calls.
    private static let liveKitMaxLayer: Int32 = 92

    public let internalId: CallSessionInternalId

    private let queue: Queue
    private let account: Account
    private let callSessionManager: CallSessionManager
    private let callVersion: String
    private let bridge: LiveKitCallBridge

    private let contextState: Promise<OngoingCallContextState?>
    public var state: Signal<OngoingCallContextState?, NoError> {
        return self.contextState.get()
    }

    private let receptionPromise = Promise<Int32?>(nil)
    public var reception: Signal<Int32?, NoError> {
        return self.receptionPromise.get()
    }

    private let audioLevelPromise = ValuePromise<Float>(0.0, ignoreRepeated: true)
    public var audioLevel: Signal<Float, NoError> {
        return self.audioLevelPromise.get()
    }

    public static var maxLayer: Int32 {
        return OngoingCallContext.liveKitMaxLayer
    }

    static let referenceImplementationVersions: Set<String> = ["10.0.0", "11.0.0"]

    public static func ignoresInitialAudioDevices(version: String) -> Bool {
        return referenceImplementationVersions.contains(version)
    }

    public static func versions(includeExperimental: Bool, includeReference: Bool) -> [(version: String, supportsVideo: Bool)] {
        return [(version: "impulsem-livekit-1", supportsVideo: true)]
    }

    /// Maps the state of the LiveKit call to the state the call session reads. Every end of the call is reported as a failure.
    static func ongoingState(for state: LiveKitCallState) -> OngoingCallContextState {
        let mappedState: OngoingCallContextState.State
        switch state {
        case .connecting:
            mappedState = .initializing
        case .connected:
            mappedState = .connected
        case .ended:
            mappedState = .failed
        }
        return OngoingCallContextState(
            state: mappedState,
            videoState: .inactive,
            remoteVideoState: .inactive,
            remoteAudioState: .active,
            remoteBatteryLevel: .normal,
            remoteAspectRatio: 0.0
        )
    }



    public init(
        account: Account,
        callSessionManager: CallSessionManager,
        internalId: CallSessionInternalId,
        callId: Int64,
        proxyServer: ProxyServerSettings?,
        initialNetworkType: NetworkType,
        updatedNetworkType: Signal<NetworkType, NoError>,
        serializedData: String?,
        dataSaving: VoiceCallDataSaving,
        derivedState: VoipDerivedState,
        key: Data,
        isOutgoing: Bool,
        video: OngoingCallVideoCapturer?,
        connections: CallSessionConnectionSet,
        maxLayer: Int32,
        version: String,
        customParameters: String?,
        allowP2P: Bool,
        enableTCP: Bool,
        enableStunMarking: Bool,
        logName: String,
        preferredVideoCodec: String?,
        inputDeviceId: String?,
        outputDeviceId: String?
    ) {
        self.internalId = internalId
        self.account = account
        self.callSessionManager = callSessionManager
        self.callVersion = version

        let queue: Queue = Queue()
        let contextState: Promise<OngoingCallContextState?> = Promise<OngoingCallContextState?>(nil)
        self.queue = queue
        self.contextState = contextState
        self.bridge = LiveKitCallBridge(reportState: { (state: LiveKitCallState) in
            queue.async {
                contextState.set(.single(OngoingCallContext.ongoingState(for: state)))
            }
        })

        cleanupCallLogs(account: account)

        contextState.set(.single(OngoingCallContext.ongoingState(for: .connecting)))
        self.receptionPromise.set(.single(4))

        let bridge: LiveKitCallBridge = self.bridge
        let parameters: String = customParameters ?? ""
        Task { @MainActor in
            bridge.start(callId: callId, version: version, parameters: parameters, authKey: key)
        }
    }

    deinit {
        let bridge: LiveKitCallBridge = self.bridge
        Task { @MainActor in
            bridge.stop()
        }
    }

    /// Ends the call. The state reports the end once the room has left or the leave deadline has passed.
    public func stop(callId: CallId? = nil, sendDebugLogs: Bool = false, debugLogValue: Promise<String?>) {
        debugLogValue.set(.single(nil))
        let bridge: LiveKitCallBridge = self.bridge
        Task { @MainActor in
            bridge.stop()
        }
    }

    /// Microphone and device controls are not routed to the LiveKit room yet.
    public func setIsMuted(_ value: Bool) {
    }

    /// Not routed to the LiveKit room yet.
    public func setIsLowBatteryLevel(_ value: Bool) {
    }

    /// Camera video is not routed to the LiveKit room yet.
    public func requestVideo(_ capturer: OngoingCallVideoCapturer) {
    }

    /// Not routed to the LiveKit room yet.
    public func setRequestedVideoAspect(_ aspect: Float) {
    }

    /// Not routed to the LiveKit room yet.
    public func disableVideo() {
    }

    /// Not routed to the LiveKit room yet.
    public func switchAudioOutput(_ deviceId: String) {
    }

    /// Not routed to the LiveKit room yet.
    public func switchAudioInput(_ deviceId: String) {
    }

    public func debugInfo() -> Signal<(String, String), NoError> {
        return .single((self.callVersion, ""))
    }

    /// Remote video frames are not routed from the LiveKit room yet.
    public func video(isIncoming: Bool) -> Signal<OngoingGroupCallContext.VideoFrameData, NoError> {
        return .complete()
    }

    /// Remote video views are not created from the LiveKit room yet.
    public func makeIncomingVideoView(completion: @escaping (OngoingCallContextPresentationCallVideoView?) -> Void) {
        completion(nil)
    }
}
