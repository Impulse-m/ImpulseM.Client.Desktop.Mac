import XCTest
@testable import ProxyUI


final class ExternalProxyGateTests: XCTestCase {
    func testDisabledFeatureBlocksExternalProxyApply() {
        let allowed: Bool = externalProxyApplyAllowed(featureEnabled: false)

        XCTAssertFalse(allowed)
    }


    func testEnabledFeatureAllowsExternalProxyApply() {
        let allowed: Bool = externalProxyApplyAllowed(featureEnabled: true)

        XCTAssertTrue(allowed)
    }
}
