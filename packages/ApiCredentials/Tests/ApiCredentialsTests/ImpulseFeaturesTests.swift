import XCTest
@testable import ApiCredentials


final class ImpulseFeaturesTests: XCTestCase {
    override func tearDown() {
        ImpulseFeatures.setPremiumPurchaseBlocked(false)
        super.tearDown()
    }


    func testHideFlagsDefaultToFalse() {
        XCTAssertFalse(ImpulseFeatures.STORIES_POSTING)
        XCTAssertFalse(ImpulseFeatures.BOOSTS)
        XCTAssertFalse(ImpulseFeatures.STARS_AND_TON)
        XCTAssertFalse(ImpulseFeatures.SECRET_CHATS)
        XCTAssertFalse(ImpulseFeatures.AI_COMPOSE)
        XCTAssertFalse(ImpulseFeatures.CHAT_WALLPAPER_AND_THEME)
        XCTAssertFalse(ImpulseFeatures.BROWSER_SETTINGS)
        XCTAssertFalse(ImpulseFeatures.COMMUNITIES)
        XCTAssertFalse(ImpulseFeatures.PAYMENT_SHIPPING_INFO)
        XCTAssertFalse(ImpulseFeatures.PROXY)
        XCTAssertFalse(ImpulseFeatures.HELP_SECTION)
        XCTAssertFalse(ImpulseFeatures.CALL_VERIFICATION)
        XCTAssertFalse(ImpulseFeatures.TEST_BACKEND)
    }


    func testVlessDefaultsToTrue() {
        XCTAssertTrue(ImpulseFeatures.VLESS)
    }


    func testPremiumPurchaseBlockedDefaultsToFalse() {
        XCTAssertFalse(ImpulseFeatures.premiumPurchaseBlocked())
        XCTAssertFalse(ImpulseFeatures.premiumFeaturesBlocked(isPremium: false))
    }


    func testPremiumFeaturesBlockedNeedsBlockedStateAndNonPremiumUser() {
        ImpulseFeatures.setPremiumPurchaseBlocked(true)

        XCTAssertTrue(ImpulseFeatures.premiumPurchaseBlocked())
        XCTAssertTrue(ImpulseFeatures.premiumFeaturesBlocked(isPremium: false))
        XCTAssertFalse(ImpulseFeatures.premiumFeaturesBlocked(isPremium: true))

        ImpulseFeatures.setPremiumPurchaseBlocked(false)

        XCTAssertFalse(ImpulseFeatures.premiumFeaturesBlocked(isPremium: false))
    }
}
