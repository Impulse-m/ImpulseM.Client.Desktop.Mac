import Foundation
import LiveKit
import TelegramVoip
import TgVoipWebrtc


/// Whether the macOS screen picker can list and share screens. ScreenCaptureKit sources need macOS 12.3.
public func macOSScreenShareSupported() -> Bool {
    if #available(macOS 12.3, *) {
        return true
    } else {
        return false
    }
}


/// One display or window that the desktop picker lists. It wraps the LiveKit capture source that the screen share track is built from.
public final class MacOSScreenPickerSource : VideoSourceMac, Equatable {
    private let titleValue: String
    private let identifier: String
    private let capturerFactory: () -> OngoingCallVideoCapturer?


    init(
        title: String,
        identifier: String,
        capturerFactory: @escaping () -> OngoingCallVideoCapturer?
    ) {
        self.titleValue = title
        self.identifier = identifier
        self.capturerFactory = capturerFactory
    }


    public static func ==(
        lhs: MacOSScreenPickerSource,
        rhs: MacOSScreenPickerSource
    ) -> Bool {
        return lhs.identifier == rhs.identifier
    }


    public func isEqual(_ another: Any) -> Bool {
        if let another = another as? MacOSScreenPickerSource {
            return another.identifier == self.identifier
        } else {
            return false
        }
    }


    public func deviceIdKey() -> String {
        return self.identifier
    }


    public func title() -> String {
        return self.titleValue
    }


    public func uniqueKey() -> String {
        return self.identifier
    }


    /// A new local screen share capturer for this source, or nil below macOS 12.3. The capturer owns the LiveKit screen share track.
    public func makeCapturer() -> OngoingCallVideoCapturer? {
        return self.capturerFactory()
    }
}


/// The displays and windows the desktop picker lists, read from `MacOSScreenCapturer`.
public enum MacOSScreenPickerListing {
    /// Lists the displays and the windows. Below macOS 12.3, or when the listing fails, a list is empty.
    public static func load() async -> (displays: [MacOSScreenPickerSource], windows: [MacOSScreenPickerSource]) {
        if #available(macOS 12.3, *) {
            let displays: [MacOSScreenCaptureSource] = (try? await MacOSScreenCapturer.sources(for: .display)) ?? []
            let windows: [MacOSScreenCaptureSource] = (try? await MacOSScreenCapturer.sources(for: .window)) ?? []
            return (
                displays: makePickerSources(sources: displays, kind: "display"),
                windows: makePickerSources(sources: windows, kind: "window")
            )
        } else {
            return (displays: [], windows: [])
        }
    }


    @available(macOS 12.3, *)
    private static func makePickerSources(
        sources: [MacOSScreenCaptureSource],
        kind: String
    ) -> [MacOSScreenPickerSource] {
        var result: [MacOSScreenPickerSource] = []
        for source: MacOSScreenCaptureSource in sources {
            let picker: MacOSScreenPickerSource = MacOSScreenPickerSource(
                title: source.name,
                identifier: "\(kind):\(source.id)",
                capturerFactory: { () -> OngoingCallVideoCapturer? in
                    return OngoingCallVideoCapturer(screenSource: source)
                }
            )
            result.append(picker)
        }
        return result
    }
}
