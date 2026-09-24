import XCTest
@testable import PongWatch_Watch_App

/// Each ability has to change something a player would notice. These check the
/// measurable consequence, not just that a flag was set.
final class AbilityEffectTests: XCTestCase {
    /// A fresh store per game: sharing one would leave the previous ability
    /// equipped and quietly contaminate the baseline it's compared against.
    private func game(with ability: Ability?) -> GameState {
        let store = ProgressionStore(defaults: UserDefaults(suiteName: "ability.\(UUID().uuidString)")!)
        if let ability, let item = UnlockCatalog.all.first(where: { $0.ability == ability }) {
            store.award(item.cost)
            _ = store.buy(item)
            store.equip(item)
        }
        let g = GameState(progression: store)
        g.startGame()
        return g
    }

    func test_everyAbilityIsReachableFromTheCatalog() {
        for ability in Ability.allCases {
            XCTAssertNotNil(UnlockCatalog.all.first { $0.ability == ability }, "\(ability) can't be bought")
        }
    }

    func test_openingShieldStartsWithASave() {
        XCTAssertTrue(game(with: .shieldStart).powerUps.hasShield(for: .bottom))
        XCTAssertFalse(game(with: nil).powerUps.hasShield(for: .bottom))
    }

    func test_stickyStartArmsTheCatch() {
        XCTAssertTrue(game(with: .stickyStart).powerUps.stickyArmed(for: .bottom))
    }

    func test_longPaddleWidensOnlyThePlayer() {
        let g = game(with: .widePaddle)
        XCTAssertGreaterThan(g.powerUps.paddleWidth(for: .bottom), GameConstants.paddleWidth)
        XCTAssertEqual(g.powerUps.paddleWidth(for: .top), GameConstants.paddleWidth)
    }

    func test_slowServeLaunchesTheBallSlower() {
        let slow = game(with: .slowServe).pendingServe!
        let normal = game(with: nil).pendingServe!
        XCTAssertLessThan(hypot(slow.dx, slow.dy), hypot(normal.dx, normal.dy))
    }

    func test_steadyClimbRaisesSpeedMoreGently() {
        XCTAssertLessThan(game(with: .steadyClimb).speedIncreasePerTier,
                          game(with: nil).speedIncreasePerTier)
    }

    func test_slowOpponentAndCalmOpponentBothEaseTheAI() {
        let baseline = game(with: nil)
        XCTAssertLessThan(game(with: .slowOpponent).aiSpeedNow(playerScore: 0),
                          baseline.aiSpeedNow(playerScore: 0))
        // The calm AI matches at zero and only pulls ahead as you score.
        XCTAssertEqual(game(with: .calmOpponent).aiSpeedNow(playerScore: 0),
                       baseline.aiSpeedNow(playerScore: 0), accuracy: 0.0001)
        XCTAssertLessThan(game(with: .calmOpponent).aiSpeedNow(playerScore: 6),
                          baseline.aiSpeedNow(playerScore: 6))
    }

    func test_luckyDropsAndBigDropsMakePickupsEasier() {
        XCTAssertLessThan(game(with: .luckyDrops).powerUps.spawnIntervalFactor, 1)
        XCTAssertGreaterThan(game(with: .bigDrops).powerUps.pickupRadiusFactor, 1)
    }

    func test_longCatchHoldsAStickyBallLonger() {
        XCTAssertGreaterThan(game(with: .longCatch).stickyHoldSeconds,
                             game(with: nil).stickyHoldSeconds)
    }

    /// The fairness rule, checked against every ability rather than one.
    func test_noAbilityLeaksIntoAMultiplayerGame() {
        for ability in Ability.allCases {
            let item = UnlockCatalog.all.first { $0.ability == ability }!
            let s = ProgressionStore(defaults: UserDefaults(suiteName: "mp.\(UUID().uuidString)")!)
            s.award(item.cost); _ = s.buy(item); s.equip(item)
            let g = GameState(progression: s)
            g.topSideIsAI = false      // a person on the other paddle
            g.startGame()
            let plain = GameState()
            plain.topSideIsAI = false
            plain.startGame()
            XCTAssertEqual(g.powerUps.paddleWidth(for: .bottom), plain.powerUps.paddleWidth(for: .bottom))
            XCTAssertEqual(g.powerUps.hasShield(for: .bottom), plain.powerUps.hasShield(for: .bottom))
            XCTAssertEqual(g.powerUps.stickyArmed(for: .bottom), plain.powerUps.stickyArmed(for: .bottom))
            XCTAssertEqual(g.speedIncreasePerTier, plain.speedIncreasePerTier, "\(ability) leaked")
            XCTAssertEqual(g.stickyHoldSeconds, plain.stickyHoldSeconds, "\(ability) leaked")
        }
    }
}
