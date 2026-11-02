import Cocoa
import Foundation
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Postbox
import TGUIKit
import TelegramVoip
import LiveKit
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


/// Holds the LiveKit call of one call session. The call is main-actor isolated, so every access runs in a main-actor task.
///
/// Media settings made before the call starts are kept and applied when it is created. The call itself keeps the media operations in order.
private final class LiveKitCallBridge: @unchecked Sendable {
    private var call: LiveKitPrivateCall?
    private var isStopped: Bool = false
    private var isMicrophoneMuted: Bool = false
    private var camera: OngoingCallVideoCapturer?
    private var audioInputId: String?
    private var audioOutputId: String?
    private let reportState: (OngoingCallContextState) -> Void
    private let reportRemoteVideo: (VideoTrack?) -> Void


    init(
        video: OngoingCallVideoCapturer?,
        inputDeviceId: String?,
        outputDeviceId: String?,
        reportState: @escaping (OngoingCallContextState) -> Void,
        reportRemoteVideo: @escaping (VideoTrack?) -> Void
    ) {
        self.camera = video
        self.audioInputId = inputDeviceId
        self.audioOutputId = outputDeviceId
        self.reportState = reportState
        self.reportRemoteVideo = reportRemoteVideo
    }


    /// Creates and starts the call. A parameter or protocol error reports a failed state at once.
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
        let created: LiveKitPrivateCall
        do {
            created = try LiveKitPrivateCall(
                callId: callId,
                versions: [version],
                parameters: parameters,
                authKey: authKey
            )
        } catch {
            self.reportState(OngoingCallContext.failedState())
            return
        }
        created.onSnapshot = { [weak self] (snapshot: LiveKitPrivateCallSnapshot) in
            self?.reportState(OngoingCallContext.ongoingState(for: snapshot))
        }
        created.onRemoteVideo = self.reportRemoteVideo
        self.call = created
        created.setMuted(self.isMicrophoneMuted)
        created.setVideo(self.camera)
        if let inputId: String = self.audioInputId {
            created.setAudioInputDevice(inputId)
        }
        if let outputId: String = self.audioOutputId {
            created.setAudioOutputDevice(outputId)
        }
        created.start()
    }


    @MainActor
    func setMuted(_ isMuted: Bool) {
        self.isMicrophoneMuted = isMuted
        self.call?.setMuted(isMuted)
    }


    @MainActor
    func requestVideo(_ capturer: OngoingCallVideoCapturer) {
        self.camera = capturer
        self.call?.setVideo(capturer)
    }


    @MainActor
    func disableVideo() {
        self.camera = nil
        self.call?.setVideo(nil)
    }


    @MainActor
    func switchAudioInput(_ deviceId: String) {
        self.audioInputId = deviceId
        self.call?.setAudioInputDevice(deviceId)
    }


    @MainActor
    func switchAudioOutput(_ deviceId: String) {
        self.audioOutputId = deviceId
        self.call?.setAudioOutputDevice(deviceId)
    }


    @MainActor
    func stop() {
        self.isStopped = true
        self.call?.stop()
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
    private let remoteVideoPromise: Promise<VideoTrack?>
    private let localVideoPromise: Promise<VideoTrack?>
    private let incomingVideoViewDisposable: MetaDisposable = MetaDisposable()

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

    /// The state before the call reports its first snapshot.
    static func initialState() -> OngoingCallContextState {
        return OngoingCallContextState(
            state: .initializing,
            videoState: .inactive,
            remoteVideoState: .inactive,
            remoteAudioState: .active,
            remoteBatteryLevel: .normal,
            remoteAspectRatio: 0.0
        )
    }

    /// The state of a call that could not be created. It has no media.
    static func failedState() -> OngoingCallContextState {
        return OngoingCallContextState(
            state: .failed,
            videoState: .inactive,
            remoteVideoState: .inactive,
            remoteAudioState: .muted,
            remoteBatteryLevel: .normal,
            remoteAspectRatio: 0.0
        )
    }

    /// Maps a snapshot of the LiveKit call to the state the call session reads. Every end of the call is reported as a failure.
    static func ongoingState(for snapshot: LiveKitPrivateCallSnapshot) -> OngoingCallContextState {
        let mappedState: OngoingCallContextState.State
        switch snapshot.connection {
        case .connecting:
            mappedState = .initializing
        case .connected:
            mappedState = .connected
        case .ended:
            mappedState = .failed
        }
        let videoState: OngoingCallContextState.VideoState
        if snapshot.localVideo != nil {
            videoState = .active
        } else {
            videoState = .inactive
        }
        let remoteVideoState: OngoingCallContextState.RemoteVideoState
        if snapshot.isRemoteVideoActive {
            remoteVideoState = .active
        } else {
            remoteVideoState = .inactive
        }
        let remoteAudioState: OngoingCallContextState.RemoteAudioState
        if snapshot.isRemoteAudioActive {
            remoteAudioState = .active
        } else {
            remoteAudioState = .muted
        }
        return OngoingCallContextState(
            state: mappedState,
            videoState: videoState,
            remoteVideoState: remoteVideoState,
            remoteAudioState: remoteAudioState,
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
        let remoteVideoPromise: Promise<VideoTrack?> = Promise<VideoTrack?>(nil)
        let localVideoPromise: Promise<VideoTrack?> = Promise<VideoTrack?>(nil)
        if let video: OngoingCallVideoCapturer = video {
            localVideoPromise.set(video.video())
        }
        self.queue = queue
        self.contextState = contextState
        self.remoteVideoPromise = remoteVideoPromise
        self.localVideoPromise = localVideoPromise
        self.bridge = LiveKitCallBridge(
            video: video,
            inputDeviceId: inputDeviceId,
            outputDeviceId: outputDeviceId,
            reportState: { (state: OngoingCallContextState) in
                queue.async {
                    contextState.set(.single(state))
                }
            },
            reportRemoteVideo: { (track: VideoTrack?) in
                remoteVideoPromise.set(.single(track))
            }
        )

        cleanupCallLogs(account: account)

        contextState.set(.single(OngoingCallContext.initialState()))
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

    /// Mutes or unmutes the microphone of the call room.
    public func setIsMuted(_ value: Bool) {
        let bridge: LiveKitCallBridge = self.bridge
        Task { @MainActor in
            bridge.setMuted(value)
        }
    }

    /// Publishes the local video of the capturer to the call room: its camera, or its screen share. The track is created on first use.
    public func requestVideo(_ capturer: OngoingCallVideoCapturer) {
        self.localVideoPromise.set(capturer.video())
        let bridge: LiveKitCallBridge = self.bridge
        Task { @MainActor in
            bridge.requestVideo(capturer)
        }
    }

    /// Removes the local video from the call room. The local video track is reported as absent.
    public func disableVideo() {
        self.localVideoPromise.set(.single(nil))
        let bridge: LiveKitCallBridge = self.bridge
        Task { @MainActor in
            bridge.disableVideo()
        }
    }

    /// Selects the audio output device of the call room.
    public func switchAudioOutput(_ deviceId: String) {
        let bridge: LiveKitCallBridge = self.bridge
        Task { @MainActor in
            bridge.switchAudioOutput(deviceId)
        }
    }

    /// Selects the audio input device of the call room.
    public func switchAudioInput(_ deviceId: String) {
        let bridge: LiveKitCallBridge = self.bridge
        Task { @MainActor in
            bridge.switchAudioInput(deviceId)
        }
    }

    public func debugInfo() -> Signal<(String, String), NoError> {
        return .single((self.callVersion, ""))
    }

    /// The remote video track of the call when `isIncoming` is true, otherwise the local camera track. Emits nil while the track does not exist.
    public func video(isIncoming: Bool) -> Signal<VideoTrack?, NoError> {
        if isIncoming {
            return self.remoteVideoPromise.get()
        }
        return self.localVideoPromise.get()
    }

    /// Renders the remote video track of the call. The view is created when the remote track exists.
    public func makeIncomingVideoView(completion: @escaping (OngoingCallContextPresentationCallVideoView?) -> Void) {
        let remoteTracks: Signal<VideoTrack?, NoError> = self.remoteVideoPromise.get()
        self.incomingVideoViewDisposable.set((remoteTracks
        |> filter { (track: VideoTrack?) -> Bool in
            return track != nil
        }
        |> take(1)).start(next: { (track: VideoTrack?) in
            guard let track: VideoTrack = track else {
                return
            }
            completion(makeLiveKitCallVideoPresentationView(track: track))
        }))
    }
}
