import SwiftUI

/// How a scored point is celebrated. The game owns one particle system, so
/// these are parameter sets for it rather than separate effects.
enum CelebrationStyle: String, Equatable {
    case sparks, explosion, confetti, shockwave
}

enum Ability: String, Equatable {
    case shieldStart, widePaddle, luckyDrops
}

/// Reads the equipped unlocks and hands the game what it needs to draw and
/// play. Built fresh where it's used, so equipping something takes effect on
/// the next game without any notification plumbing.
struct UnlockEffects {
    let paddleColor: Color
    let ballColor: Color
    let celebration: CelebrationStyle
    let abilities: Set<Ability>
    let title: String

    /// - Parameter allowAbilities: false in multiplayer, where a match has to
    ///   be decided by play rather than by who has unlocked more.
    init(store: ProgressionStore = ProgressionStore(), allowAbilities: Bool = true) {
        paddleColor = Self.paddleColor(store.equippedItem(in: .paddleSkin)?.id)
        ballColor = Self.ballColor(store.equippedItem(in: .ballSkin)?.id)
        celebration = Self.celebration(store.equippedItem(in: .celebration)?.id)
        title = store.equippedItem(in: .title)?.name ?? "Rookie"
        if allowAbilities, let id = store.equipped(in: .ability),
           let ability = Self.ability(id) {
            abilities = [ability]
        } else {
            abilities = []
        }
    }

    private static func paddleColor(_ id: String?) -> Color {
        switch id {
        case "paddle.gold": return GameConstants.goldPaddle
        case "paddle.neon": return GameConstants.neonPaddle
        default:            return .white
        }
    }

    private static func ballColor(_ id: String?) -> Color {
        switch id {
        case "ball.ember": return GameConstants.emberBall
        case "ball.ice":   return GameConstants.iceBall
        default:           return .white
        }
    }

    private static func celebration(_ id: String?) -> CelebrationStyle {
        switch id {
        case "celebration.explosion": return .explosion
        case "celebration.confetti":  return .confetti
        case "celebration.shockwave": return .shockwave
        default:                      return .sparks
        }
    }

    private static func ability(_ id: String) -> Ability? {
        switch id {
        case "ability.shieldStart": return .shieldStart
        case "ability.widePaddle":  return .widePaddle
        case "ability.luckyDrops":  return .luckyDrops
        default:                    return nil
        }
    }
}

/// Particle settings per celebration. One system, four looks.
struct CelebrationSpec {
    let count: Int
    let minSpeed: CGFloat
    let maxSpeed: CGFloat
    let minLifespan: CGFloat
    let maxLifespan: CGFloat
    let radiusFactor: CGFloat
    let palette: [(CGFloat, CGFloat, CGFloat)]
    /// True for the shockwave: evenly spaced, one speed, so it reads as a ring.
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
                                   palette: GameConstants.particlePalette,
                                   isRing: false)
        case .explosion:
            return CelebrationSpec(count: 34, minSpeed: 0.7, maxSpeed: 1.8,
                                   minLifespan: 0.35, maxLifespan: 0.75,
                                   radiusFactor: 0.75,
                                   palette: [(1.00, 0.35, 0.05), (1.00, 0.60, 0.10),
                                             (1.00, 0.85, 0.30), (0.85, 0.15, 0.05)],
                                   isRing: false)
        case .confetti:
            return CelebrationSpec(count: 30, minSpeed: 0.25, maxSpeed: 0.9,
                                   minLifespan: 0.8, maxLifespan: 1.4,
                                   radiusFactor: 0.45,
                                   palette: [(1.00, 0.30, 0.45), (0.30, 0.75, 1.00),
                                             (1.00, 0.90, 0.25), (0.45, 1.00, 0.50),
                                             (0.80, 0.45, 1.00)],
                                   isRing: false)
        case .shockwave:
            return CelebrationSpec(count: 26, minSpeed: 1.1, maxSpeed: 1.1,
                                   minLifespan: 0.45, maxLifespan: 0.45,
                                   radiusFactor: 0.35,
                                   palette: [(0.75, 0.95, 1.00), (1.00, 1.00, 1.00)],
                                   isRing: true)
        }
    }
}
