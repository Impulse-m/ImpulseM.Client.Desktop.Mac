import XCTest
@testable import ApiCredentials


final class ApiEnvironmentTests: XCTestCase {
    func testGroupIsTeamIdDotBundleId() {
        let expected: String = ApiEnvironment.teamId + "." + ApiEnvironment.bundleId
        XCTAssertEqual(ApiEnvironment.group, expected)
    }


    func testBundleIdIsImpulseMacBundle() {
        XCTAssertEqual(ApiEnvironment.bundleId, "net.impulsem.messenger.mac")
    }


    func testTeamIdIsBrandPlaceholderUntilSecretIsPresent() {
        XCTAssertEqual(ApiEnvironment.teamId, ImpulseBrand.teamIdPlaceholder)
    }


    func testApiIdEqualsBrandApiId() {
        XCTAssertEqual(ApiEnvironment.apiId, 4)
        XCTAssertEqual(ApiEnvironment.apiId, ImpulseBrand.apiId)
    }
}
