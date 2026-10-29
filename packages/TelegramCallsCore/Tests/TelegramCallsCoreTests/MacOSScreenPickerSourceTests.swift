import XCTest
@testable import TelegramCallsCore


final class MacOSScreenPickerSourceTests: XCTestCase {
    func testSourcesWithSameIdentifierAreEqual() {
        let first: MacOSScreenPickerSource = MacOSScreenPickerSource(
            title: "Built-in Display",
            identifier: "display:1",
            capturerFactory: { () -> OngoingCallVideoCapturer? in
                return nil
            }
        )
        let second: MacOSScreenPickerSource = MacOSScreenPickerSource(
            title: "Renamed Display",
            identifier: "display:1",
            capturerFactory: { () -> OngoingCallVideoCapturer? in
                return nil
            }
        )
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.isEqual(second))
    }

    func testSourcesWithDifferentIdentifiersAreNotEqual() {
        let display: MacOSScreenPickerSource = MacOSScreenPickerSource(
            title: "Display",
            identifier: "display:1",
            capturerFactory: { () -> OngoingCallVideoCapturer? in
                return nil
            }
        )
        let window: MacOSScreenPickerSource = MacOSScreenPickerSource(
            title: "Window",
            identifier: "window:1",
            capturerFactory: { () -> OngoingCallVideoCapturer? in
                return nil
            }
        )
        XCTAssertNotEqual(display, window)
        XCTAssertFalse(display.isEqual(window))
    }

    func testKeysAndTitleExposeTheIdentifierAndName() {
        let source: MacOSScreenPickerSource = MacOSScreenPickerSource(
            title: "Window",
            identifier: "window:42",
            capturerFactory: { () -> OngoingCallVideoCapturer? in
                return nil
            }
        )
        XCTAssertEqual(source.uniqueKey(), "window:42")
        XCTAssertEqual(source.deviceIdKey(), "window:42")
        XCTAssertEqual(source.title(), "Window")
    }

    func testMakeCapturerReturnsWhatTheFactoryReturns() {
        let source: MacOSScreenPickerSource = MacOSScreenPickerSource(
            title: "Display",
            identifier: "display:1",
            capturerFactory: { () -> OngoingCallVideoCapturer? in
                return nil
            }
        )
        XCTAssertNil(source.makeCapturer())
    }

    func testScreenShareSupportMatchesMacOS123() {
        let minimum: OperatingSystemVersion = OperatingSystemVersion(majorVersion: 12, minorVersion: 3, patchVersion: 0)
        let expected: Bool = ProcessInfo.processInfo.isOperatingSystemAtLeast(minimum)
        XCTAssertEqual(macOSScreenShareSupported(), expected)
    }
}
