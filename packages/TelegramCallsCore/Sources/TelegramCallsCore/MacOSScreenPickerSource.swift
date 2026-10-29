import AppKit
import Foundation
import LiveKit
import TelegramVoip


/// Whether the macOS screen picker can list and share screens. ScreenCaptureKit sources need macOS 12.3.
public func macOSScreenShareSupported() -> Bool {
    if #available(macOS 12.3, *) {
        return true
    } else {
        return false
    }
}


/// One display or window that the desktop picker lists. It wraps the LiveKit capture source that the screen share track is built from.
public final class MacOSScreenPickerSource : CallCaptureSource, Equatable {
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
            if let window: MacOSWindow = source as? MacOSWindow {
                let title: String
                if let windowTitle: String = window.title, !windowTitle.isEmpty {
                    title = windowTitle
                } else {
                    title = window.owningApplication?.applicationName ?? ""
                }
                let picker: MacOSScreenPickerSource = MacOSScreenPickerSource(
                    title: title,
                    identifier: "\(kind):\(window.windowID)",
                    capturerFactory: { () -> OngoingCallVideoCapturer? in
                        return OngoingCallVideoCapturer(screenSource: source)
                    }
                )
                result.append(picker)
            } else if let display: MacOSDisplay = source as? MacOSDisplay {
                let picker: MacOSScreenPickerSource = MacOSScreenPickerSource(
                    title: screenName(displayID: display.displayID),
                    identifier: "\(kind):\(display.displayID)",
                    capturerFactory: { () -> OngoingCallVideoCapturer? in
                        return OngoingCallVideoCapturer(screenSource: source)
                    }
                )
                result.append(picker)
            }
        }
        return result
    }


    /// The localized name of the screen that shows `displayID`, or an empty string when no screen matches.
    private static func screenName(displayID: CGDirectDisplayID) -> String {
        for screen: NSScreen in NSScreen.screens {
            let screenNumber: NSNumber? = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            if screenNumber?.uint32Value == displayID {
                return screen.localizedName
            }
        }
        return ""
    }
}
