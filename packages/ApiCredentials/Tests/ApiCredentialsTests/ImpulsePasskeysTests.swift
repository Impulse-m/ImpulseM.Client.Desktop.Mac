import XCTest
@testable import ApiCredentials


final class ImpulsePasskeysTests: XCTestCase {
    func testPasskeysAreHiddenUntilRelyingPartyIsConfigured() {
        XCTAssertFalse(ImpulsePasskeys.isEnabled)
    }
}
