import XCTest
import SwiftUI
@testable import PongWatch_Watch_App

final class PointsRulesTests: XCTestCase {
    /// Points come from playing at all, so a solo player on their wrist still
    /// makes progress, with winning worth more.
    func test_everyRallyPointEarnsOne() {
        XCTAssertEqual(PointsRules.award(scored: 7, won: false, newHighScore: false), 7)
    }

    func test_winningAddsABonusOnTopOfTheRallyPoints() {
        XCTAssertEqual(PointsRules.award(scored: 5, won: true, newHighScore: false),
                       5 + PointsRules.winBonus)
    }

    func test_aNewHighScoreIsWorthABonusToo() {
        XCTAssertEqual(PointsRules.award(scored: 3, won: false, newHighScore: true),
                       3 + PointsRules.highScoreBonus)
    }

    func test_losingWithoutScoringStillEarnsNothingRatherThanGoingNegative() {
        XCTAssertEqual(PointsRules.award(scored: 0, won: false, newHighScore: false), 0)
    }
}

final class UnlockCatalogTests: XCTestCase {
    func test_everyItemHasAUniqueIDSoProgressCantCollide() {
        let ids = UnlockCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// A full ten in every category, so no section looks half-finished.
    func test_everyCategoryHasTenItems() {
        for category in UnlockCategory.allCases {
            let count = UnlockCatalog.all.filter { $0.category == category }.count
            XCTAssertEqual(count, 10, "\(category.label) has \(count)")
        }
    }

    /// Each item has to carry what it actually does, or it's a name and a
    /// price with nothing behind it.
    func test_everyItemCarriesItsEffect() {
        for item in UnlockCatalog.all {
            switch item.category {
            case .paddleSkin, .ballSkin:
                XCTAssertNotNil(item.color, "\(item.id) has no colour")
            case .celebration:
                XCTAssertNotNil(item.celebration, "\(item.id) has no celebration")
            case .ability:
                XCTAssertNotNil(item.ability, "\(item.id) does nothing")
            case .title:
                XCTAssertFalse(item.name.isEmpty)
            }
        }
    }

    /// Two skins that look the same are two prices for one thing.
    func test_skinColoursAreAllDistinctWithinTheirCategory() {
        for category in [UnlockCategory.paddleSkin, .ballSkin] {
            let colours = UnlockCatalog.all.filter { $0.category == category }.compactMap { $0.color?.description }
            XCTAssertEqual(Set(colours).count, colours.count, "\(category.label) repeats a colour")
        }
    }

    func test_everyCelebrationAndAbilityIsUsedExactlyOnce() {
        let styles = UnlockCatalog.all.compactMap(\.celebration)
        XCTAssertEqual(Set(styles).count, styles.count, "a celebration is sold twice")
        XCTAssertEqual(Set(styles).count, CelebrationStyle.allCases.count, "a celebration is unreachable")
        let abilities = UnlockCatalog.all.compactMap(\.ability)
        XCTAssertEqual(Set(abilities).count, abilities.count, "an ability is sold twice")
        XCTAssertEqual(Set(abilities).count, Ability.allCases.count, "an ability is unreachable")
    }

    func test_thereIsSomethingToBuyInEveryCategory() {
        for category in UnlockCategory.allCases {
            XCTAssertFalse(UnlockCatalog.all.filter { $0.category == category }.isEmpty,
                           "\(category) has nothing to unlock")
        }
    }

    /// The first real unlock has to be reachable in a session or two, or the
    /// system reads as broken rather than aspirational.
    func test_theCheapestPurchaseIsReachableInAboutTwoGames() {
        let cheapestPaid = UnlockCatalog.all.filter { $0.cost > 0 }.map(\.cost).min() ?? .max
        XCTAssertLessThanOrEqual(cheapestPaid, 2 * PointsRules.winBonus)
    }

    /// Every category ships with a free default, so the game never has to
    /// render an empty slot.
    func test_everyCategoryHasAFreeDefault() {
        for category in UnlockCategory.allCases where category != .ability {
            XCTAssertTrue(UnlockCatalog.all.contains { $0.category == category && $0.cost == 0 },
                          "\(category) has no default")
        }
    }

    /// Abilities change play, so they must never apply in multiplayer.
    func test_abilitiesAreMarkedSinglePlayerOnly() {
        for item in UnlockCatalog.all where item.category == .ability {
            XCTAssertTrue(item.singlePlayerOnly, "\(item.id) would unbalance a match")
        }
        for item in UnlockCatalog.all where item.category != .ability {
            XCTAssertFalse(item.singlePlayerOnly, "\(item.id) is cosmetic and should show everywhere")
        }
    }
}

final class ProgressionStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "progression.tests.\(UUID().uuidString)")
    }

    private func store() -> ProgressionStore { ProgressionStore(defaults: defaults) }

    /// Free items are owned from the start, so purchase tests need a paid one.
    private var cheapestPaid: Unlockable {
        UnlockCatalog.all.filter { $0.cost > 0 }.min { $0.cost < $1.cost }!
    }

    func test_pointsAccumulateAcrossGames() {
        let s = store()
        s.award(12)
        s.award(8)
        XCTAssertEqual(s.availablePoints, 20)
        XCTAssertEqual(s.lifetimePoints, 20)
    }

    func test_buyingSpendsPointsAndUnlocksTheItem() {
        let s = store()
        let item = cheapestPaid
        s.award(item.cost + 5)
        XCTAssertTrue(s.buy(item))
        XCTAssertTrue(s.isUnlocked(item))
        XCTAssertEqual(s.availablePoints, 5, "cost is deducted")
        XCTAssertEqual(s.lifetimePoints, item.cost + 5, "lifetime total is a record, not a wallet")
    }

    func test_cannotBuyWhatYouCannotAfford() {
        let s = store()
        let item = UnlockCatalog.all.max { $0.cost < $1.cost }!
        s.award(item.cost - 1)
        XCTAssertFalse(s.buy(item))
        XCTAssertFalse(s.isUnlocked(item))
        XCTAssertEqual(s.availablePoints, item.cost - 1, "a refused purchase must not charge")
    }

    func test_buyingTwiceDoesNotChargeTwice() {
        let s = store()
        let item = cheapestPaid
        s.award(item.cost * 3)
        XCTAssertTrue(s.buy(item))
        let after = s.availablePoints
        XCTAssertFalse(s.buy(item), "already owned")
        XCTAssertEqual(s.availablePoints, after)
    }

    func test_equippingRemembersTheChoicePerCategory() {
        let s = store()
        let skin = UnlockCatalog.all.first { $0.category == .paddleSkin && $0.cost > 0 }!
        s.award(skin.cost)
        _ = s.buy(skin)
        s.equip(skin)
        XCTAssertEqual(s.equipped(in: .paddleSkin), skin.id)
    }

    func test_cannotEquipSomethingNotOwned() {
        let s = store()
        let skin = UnlockCatalog.all.first { $0.category == .paddleSkin && $0.cost > 0 }!
        s.equip(skin)
        XCTAssertNil(s.equipped(in: .paddleSkin), "a locked skin must not become equipped")
    }

    /// Progress that vanishes on relaunch is worse than no progress at all.
    func test_progressSurvivesANewStoreOverTheSameDefaults() {
        let item = cheapestPaid
        let first = store()
        first.award(item.cost)
        _ = first.buy(item)
        first.equip(item)

        let reopened = ProgressionStore(defaults: defaults)
        XCTAssertTrue(reopened.isUnlocked(item))
        XCTAssertEqual(reopened.equipped(in: item.category), item.id)
    }
}

final class ProgressionEarningTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ProgressionStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "progression.earn.\(UUID().uuidString)")
        store = ProgressionStore(defaults: defaults)
    }

    /// Losing a single-player game still banks what you scored, so a bad run
    /// isn't wasted time.
    func test_singlePlayerGameOverBanksTheScore() {
        let game = GameState(highScoreStore: HighScoreStore(defaults: defaults),
                             hapticPlayer: FakeHapticPlayer(),
                             progression: store)
        game.phase = .playing
        game.score = 4
        game.ball = Ball(position: CGPoint(x: 0.5, y: 1.2), velocity: CGVector(dx: 0, dy: 0.5))
        game.update(dt: 0.01)

        XCTAssertEqual(game.phase, .gameOver)
        // 4 scored plus the high-score bonus, since any score beats a fresh 0.
        XCTAssertEqual(store.availablePoints,
                       PointsRules.award(scored: 4, won: false, newHighScore: true))
    }

    /// Points are banked once per game, not once per frame after it ends.
    func test_pointsAreNotAwardedRepeatedlyAfterGameOver() {
        let game = GameState(highScoreStore: HighScoreStore(defaults: defaults),
                             hapticPlayer: FakeHapticPlayer(),
                             progression: store)
        game.phase = .playing
        game.score = 2
        game.ball = Ball(position: CGPoint(x: 0.5, y: 1.2), velocity: CGVector(dx: 0, dy: 0.5))
        game.update(dt: 0.01)
        let afterFirst = store.availablePoints
        for _ in 0..<10 { game.update(dt: 0.01) }
        XCTAssertEqual(store.availablePoints, afterFirst)
    }
}

final class MultiplayerProgressionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ProgressionStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "progression.mp.\(UUID().uuidString)")
        store = ProgressionStore(defaults: defaults)
    }

    /// Winning a match against a person is the biggest earner in the game.
    @MainActor
    func test_winningAMatchPaysTheWinBonus() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake, progression: store)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.startMatch(winningScore: 1)
        try? await Task.sleep(nanoseconds: 50_000_000)

        state.finishMatchForTests(winner: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertGreaterThanOrEqual(store.availablePoints, PointsRules.winBonus)
    }

    /// Losing still banks the points you scored on the way.
    @MainActor
    func test_losingBanksTheRallyPointsWithoutTheBonus() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake, progression: store)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.startMatch(winningScore: 1)
        try? await Task.sleep(nanoseconds: 50_000_000)

        state.finishMatchForTests(winner: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertLessThan(store.availablePoints, PointsRules.winBonus)
    }
}

final class CategoryProgressTests: XCTestCase {
    private var store: ProgressionStore!

    override func setUp() {
        super.setUp()
        store = ProgressionStore(defaults: UserDefaults(suiteName: "cat.\(UUID().uuidString)")!)
    }

    /// A collapsed section still has to say where you stand, or closing it
    /// hides the only sense of progress.
    func test_ownedCountStartsAtTheFreeDefaults() {
        XCTAssertEqual(store.ownedCount(in: .paddleSkin), 1, "the free default is owned")
        XCTAssertEqual(store.ownedCount(in: .ability), 0, "abilities have no free default")
    }

    func test_ownedCountRisesWithPurchases() {
        let item = UnlockCatalog.all.first { $0.category == .ballSkin && $0.cost > 0 }!
        store.award(item.cost)
        _ = store.buy(item)
        XCTAssertEqual(store.ownedCount(in: .ballSkin), 2)
        XCTAssertEqual(store.totalCount(in: .ballSkin), 10)
    }
}
