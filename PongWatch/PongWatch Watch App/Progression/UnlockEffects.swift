import SwiftUI

/// Reads the equipped unlocks and hands the game what it needs to draw and
/// play. Built fresh where it's used, so equipping something takes effect on
/// the next game without any notification plumbing.
struct UnlockEffects {
    let paddleColor: Color
    let ballColor: Color
    let celebration: CelebrationStyle
    let ability: Ability?
    let title: String

    /// Kept for the fairness tests and older call sites that ask "which
    /// abilities are active" rather than "which one".
    var abilities: Set<Ability> { ability.map { [$0] } ?? [] }

    /// - Parameter allowAbilities: false in multiplayer, where a match has to
    ///   be decided by play rather than by who has unlocked more.
    init(store: ProgressionStore = ProgressionStore(), allowAbilities: Bool = true) {
        paddleColor = store.equippedItem(in: .paddleSkin)?.color ?? .white
        ballColor = store.equippedItem(in: .ballSkin)?.color ?? .white
        celebration = store.equippedItem(in: .celebration)?.celebration ?? .sparks
        title = store.equippedItem(in: .title)?.name ?? "Rookie"
        // Abilities have no free default: nothing is equipped until bought.
        ability = allowAbilities
            ? store.equipped(in: .ability).flatMap { UnlockCatalog.item(id: $0)?.ability }
            : nil
    }
}

/// Particle settings per celebration. One system, ten looks.
struct CelebrationSpec {
    let count: Int
    let minSpeed: CGFloat
    let maxSpeed: CGFloat
    let minLifespan: CGFloat
    let maxLifespan: CGFloat
    let radiusFactor: CGFloat
    let palette: [(CGFloat, CGFloat, CGFloat)]
    /// Evenly spaced at one speed, so it reads as a ring rather than a spray.
    let isRing: Bool

    static func `for`(_ style: CelebrationStyle) -> CelebrationSpec {
        switch style {
        case .sparks:
            return CelebrationSpec(count: GameConstants.particlesPerBurst,
                                   minSpeed: GameConstants.particleMinSpeed,
                                   maxSpeed: GameConstants.particleMaxSpeed,
                                   minLifespan: GameConstants.particleMinLifespan,
                                   maxLifespan: GameConstants.particleMaxLifespan,
                                   radiusFactor: GameConstants.particleRadiusFactor,
                                   palette: GameConstants.particlePalette, isRing: false)
        case .explosion:
            return CelebrationSpec(count: 34, minSpeed: 0.7, maxSpeed: 1.8,
                                   minLifespan: 0.35, maxLifespan: 0.75, radiusFactor: 0.75,
                                   palette: [(1.00, 0.35, 0.05), (1.00, 0.60, 0.10),
                                             (1.00, 0.85, 0.30), (0.85, 0.15, 0.05)], isRing: false)
        case .confetti:
            return CelebrationSpec(count: 30, minSpeed: 0.25, maxSpeed: 0.9,
                                   minLifespan: 0.8, maxLifespan: 1.4, radiusFactor: 0.45,
                                   palette: [(1.00, 0.30, 0.45), (0.30, 0.75, 1.00),
                                             (1.00, 0.90, 0.25), (0.45, 1.00, 0.50),
                                             (0.80, 0.45, 1.00)], isRing: false)
        case .shockwave:
            return CelebrationSpec(count: 26, minSpeed: 1.1, maxSpeed: 1.1,
                                   minLifespan: 0.45, maxLifespan: 0.45, radiusFactor: 0.35,
                                   palette: [(0.75, 0.95, 1.00), (1.00, 1.00, 1.00)], isRing: true)
        case .fireworks:
            return CelebrationSpec(count: 44, minSpeed: 1.0, maxSpeed: 2.1,
                                   minLifespan: 0.25, maxLifespan: 0.55, radiusFactor: 0.40,
                                   palette: [(1.00, 0.20, 0.30), (0.25, 0.60, 1.00),
                                             (1.00, 0.95, 0.35), (0.40, 1.00, 0.55),
                                             (1.00, 0.55, 0.15)], isRing: false)
        case .emberRain:
            // Slow and heavy: the specks hang and drift instead of snapping out.
            return CelebrationSpec(count: 18, minSpeed: 0.12, maxSpeed: 0.40,
                                   minLifespan: 1.1, maxLifespan: 1.8, radiusFactor: 0.55,
                                   palette: [(1.00, 0.45, 0.10), (0.90, 0.25, 0.05),
                                             (1.00, 0.70, 0.25)], isRing: false)
        case .starburst:
            return CelebrationSpec(count: 12, minSpeed: 1.4, maxSpeed: 1.4,
                                   minLifespan: 0.6, maxLifespan: 0.6, radiusFactor: 0.60,
                                   palette: [(1.00, 1.00, 0.85), (1.00, 0.90, 0.40)], isRing: true)
        case .pulse:
            return CelebrationSpec(count: 40, minSpeed: 0.75, maxSpeed: 0.75,
                                   minLifespan: 0.9, maxLifespan: 0.9, radiusFactor: 0.25,
                                   palette: [(1.00, 1.00, 1.00)], isRing: true)
        case .rainbow:
            return CelebrationSpec(count: 36, minSpeed: 0.4, maxSpeed: 1.3,
                                   minLifespan: 0.6, maxLifespan: 1.2, radiusFactor: 0.50,
                                   palette: [(1.00, 0.20, 0.20), (1.00, 0.60, 0.15),
                                             (1.00, 0.95, 0.25), (0.35, 0.90, 0.40),
                                             (0.25, 0.65, 1.00), (0.55, 0.35, 0.95),
                                             (0.95, 0.40, 0.85)], isRing: false)
        case .meteor:
            // Few, large and fast — reads as several heavy streaks.
            return CelebrationSpec(count: 7, minSpeed: 1.5, maxSpeed: 2.4,
                                   minLifespan: 0.5, maxLifespan: 0.9, radiusFactor: 1.10,
                                   palette: [(1.00, 0.80, 0.55), (1.00, 0.55, 0.20)], isRing: false)
        }
    }
}

/// The single-player tuning one equipped ability applies. Neutral by default,
/// so a game with nothing equipped plays exactly as it always did.
struct AbilityTuning {
    var ballSpeedFactor: CGFloat = 1
    var speedTierFactor: CGFloat = 1
    var aiSpeedFactor: CGFloat = 1
    var aiRampFactor: CGFloat = 1
    var paddleWidthFactor: CGFloat = 1
    var spawnIntervalFactor: CGFloat = 1
    var pickupRadiusFactor: CGFloat = 1
    var stickyHoldFactor: CGFloat = 1
    var startsWithShield = false
    var startsWithSticky = false

    static func `for`(_ ability: Ability?) -> AbilityTuning {
        var t = AbilityTuning()
        switch ability {
        case .shieldStart:   t.startsWithShield = true
        case .stickyStart:   t.startsWithSticky = true
        case .widePaddle:    t.paddleWidthFactor = 1.25
        case .slowServe:     t.ballSpeedFactor = 0.85
        case .steadyClimb:   t.speedTierFactor = 0.6
        case .slowOpponent:  t.aiSpeedFactor = 0.85
        case .calmOpponent:  t.aiRampFactor = 0.5
        case .luckyDrops:    t.spawnIntervalFactor = 0.6
        case .bigDrops:      t.pickupRadiusFactor = 1.6
        case .longCatch:     t.stickyHoldFactor = 1.8
        case nil:            break
        }
        return t
    }
}
