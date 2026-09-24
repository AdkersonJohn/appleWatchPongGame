import XCTest
import SwiftUI
@testable import PongWatch_Watch_App

final class UnlockEffectsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ProgressionStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "unlock.fx.\(UUID().uuidString)")
        store = ProgressionStore(defaults: defaults)
    }

    private func own(_ id: String) -> Unlockable {
        let item = UnlockCatalog.item(id: id)!
        store.award(item.cost)
        _ = store.buy(item)
        return item
    }

    /// A fresh player still gets a full set of visuals, never a blank paddle.
    func test_defaultsAreUsedBeforeAnythingIsBought() {
        let fx = UnlockEffects(store: store)
        XCTAssertEqual(fx.paddleColor, .white)
        XCTAssertEqual(fx.ballColor, .white)
        XCTAssertEqual(fx.celebration, .sparks)
        XCTAssertTrue(fx.abilities.isEmpty)
    }

    func test_equippingASkinChangesTheColour() {
        store.equip(own("paddle.gold"))
        XCTAssertEqual(UnlockEffects(store: store).paddleColor, GameConstants.goldPaddle)
    }

    func test_equippingACelebrationChangesTheBurst() {
        store.equip(own("celebration.confetti"))
        XCTAssertEqual(UnlockEffects(store: store).celebration, .confetti)
    }

    /// Owning an ability isn't enough — it only counts while equipped.
    func test_anAbilityAppliesOnlyWhenEquipped() {
        let ability = own("ability.widePaddle")
        XCTAssertTrue(UnlockEffects(store: store).abilities.isEmpty)
        store.equip(ability)
        XCTAssertTrue(UnlockEffects(store: store).abilities.contains(.widePaddle))
    }

    /// The fairness rule: abilities never reach a match against a person.
    func test_multiplayerStripsAbilitiesButKeepsCosmetics() {
        store.equip(own("ability.widePaddle"))
        store.equip(own("paddle.neon"))
        let fx = UnlockEffects(store: store, allowAbilities: false)
        XCTAssertTrue(fx.abilities.isEmpty, "a match must be decided by play, not by grinding")
        XCTAssertEqual(fx.paddleColor, GameConstants.neonPaddle, "cosmetics still show off")
    }
}

final class AbilityApplicationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ProgressionStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ability.apply.\(UUID().uuidString)")
        store = ProgressionStore(defaults: defaults)
    }

    private func equip(_ id: String) {
        let item = UnlockCatalog.item(id: id)!
        store.award(item.cost)
        _ = store.buy(item)
        store.equip(item)
    }

    func test_openingShieldStartsTheGameWithASave() {
        equip("ability.shieldStart")
        let game = GameState(progression: store)
        game.startGame()
        XCTAssertTrue(game.powerUps.hasShield(for: .bottom))
    }

    func test_longPaddleWidensOnlyThePlayersPaddle() {
        equip("ability.widePaddle")
        let game = GameState(progression: store)
        game.startGame()
        XCTAssertGreaterThan(game.powerUps.paddleWidth(for: .bottom), GameConstants.paddleWidth)
        XCTAssertEqual(game.powerUps.paddleWidth(for: .top), GameConstants.paddleWidth,
                       "the AI doesn't get your unlocks")
    }

    func test_abilitiesAreNotAppliedInAMultiplayerGame() {
        equip("ability.shieldStart")
        let game = GameState(progression: store)
        game.topSideIsAI = false          // multiplayer: the top paddle is a person
        game.startGame()
        XCTAssertFalse(game.powerUps.hasShield(for: .bottom))
    }
}

final class CelebrationTests: XCTestCase {
    private func burst(_ style: CelebrationStyle) -> [Particle] {
        let game = GameState()
        game.celebration = style
        game.spawnScoreBurst(atX: 0.5)
        return game.particles
    }

    /// Each celebration has to be visibly different, or the unlock is a con.
    func test_everyCelebrationLooksDifferentFromTheDefault() {
        let sparks = burst(.sparks)
        for style in [CelebrationStyle.explosion, .confetti, .shockwave] {
            let other = burst(style)
            let differs = other.count != sparks.count
                || other.map(\.radius).max() != sparks.map(\.radius).max()
                || Set(other.map(\.red)) != Set(sparks.map(\.red))
            XCTAssertTrue(differs, "\(style) is indistinguishable from sparks")
        }
    }

    /// A shockwave reads as a ring, so its particles all travel at one speed.
    func test_shockwaveTravelsOutwardAtOneSpeed() {
        let speeds = burst(.shockwave).map { hypot($0.velocity.dx, $0.velocity.dy) }
        XCTAssertEqual(Set(speeds.map { ($0 * 1000).rounded() }).count, 1)
    }

    func test_confettiUsesManyColours() {
        let colours = Set(burst(.confetti).map { "\($0.red)-\($0.green)-\($0.blue)" })
        XCTAssertGreaterThan(colours.count, 2)
    }
}
