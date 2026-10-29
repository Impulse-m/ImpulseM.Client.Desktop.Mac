import Foundation
import AVFoundation
import LiveKit
import TelegramVoip
import Localization
import ColorPalette
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import SystemPermissions
import ProxyUtils

public struct DesktopCapturerObjectWrapper : Equatable {
    public static func == (lhs: DesktopCapturerObjectWrapper, rhs: DesktopCapturerObjectWrapper) -> Bool {
        if !lhs.source.isEqual(rhs.source) {
            return false
        }
        if lhs.isAvailableToStream != rhs.isAvailableToStream {
            return false
        }
        return true
    }

    public let source: CallCaptureSource
    public let isAvailableToStream: Bool
    public init(source: CallCaptureSource, isAvailableToStream: Bool) {
        self.source = source
        self.isAvailableToStream = isAvailableToStream
    }
}

public final class CameraCaptureDevice : CallCaptureSource, Equatable {
    public func isEqual(_ another: Any) -> Bool {
        if let another = another as? CallCaptureSource {
            return another.uniqueKey() == self.uniqueKey()
        } else {
            return false
        }
    }
    
    public let device: AVCaptureDevice
    public init(_ device: AVCaptureDevice) {
        self.device = device
    }
    public func deviceIdKey() -> String {
        return self.device.uniqueID
    }
    public func title() -> String {
        return device.localizedName
    }
    public func uniqueKey() -> String {
        return self.device.uniqueID
    }
    public static func ==(lhs: CameraCaptureDevice, rhs: CameraCaptureDevice) -> Bool {
        return lhs.device == rhs.device
    }
    /// The LiveKit camera track of this device. `LiveKitVideoSources` builds it, the same factory the call capturer uses.
    public func makeLiveKitVideoTrack() async -> LocalVideoTrack? {
        return await LiveKitVideoSources.createCameraTrack(captureCode: .front, deviceId: self.device.uniqueID)
    }
}
