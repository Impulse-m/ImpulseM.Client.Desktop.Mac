import XCTest
@testable import TelegramCallsCore


final class LiveKitGroupCallRefusalTests: XCTestCase {
    func testE2ECallIsRefused() {
        XCTAssertTrue(LiveKitGroupCallRefusal.refusesCall(hasE2EContext: true, isConference: false, isStream: false))
    }


    func testConferenceCallIsRefused() {
        XCTAssertTrue(LiveKitGroupCallRefusal.refusesCall(hasE2EContext: false, isConference: true, isStream: false))
    }


    func testStreamCallIsRefused() {
        XCTAssertTrue(LiveKitGroupCallRefusal.refusesCall(hasE2EContext: false, isConference: false, isStream: true))
    }


    func testPlainCallIsNotRefused() {
        XCTAssertFalse(LiveKitGroupCallRefusal.refusesCall(hasE2EContext: false, isConference: false, isStream: false))
    }


    func testRtcAnswerIsAccepted() {
        XCTAssertFalse(LiveKitGroupCallRefusal.refusesAnswer(connectionMode: .rtc))
    }


    func testBroadcastAnswerIsRefused() {
        XCTAssertTrue(LiveKitGroupCallRefusal.refusesAnswer(connectionMode: .broadcast(isExternalStream: false)))
    }


    func testExternalStreamAnswerIsRefused() {
        XCTAssertTrue(LiveKitGroupCallRefusal.refusesAnswer(connectionMode: .broadcast(isExternalStream: true)))
    }
}
