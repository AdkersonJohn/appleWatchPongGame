import Foundation
import SwiftUI
import CoreGraphics

/// How points are earned. Pure, so the balance can be argued with in a test
/// rather than by replaying the game.
enum PointsRules {
    /// Paid on winning a multiplayer match.
    static let winBonus = 25
    /// Paid on beating your own single-player best.
    static let highScoreBonus = 15

    /// Points banked for one finished game.
    static func award(scored: Int, won: Bool, newHighScore: Bool) -> Int {
        max(0, scored) + (won ? winBonus : 0) + (newHighScore ? highScoreBonus : 0)
    }
}

enum UnlockCategory: String, CaseIterable, Codable {
    case celebration
    case paddleSkin
    case ballSkin
    case title
    case ability

    /// Shown as a section header; short enough for a 40mm screen.
    var label: String {
        switch self {
        case .celebration: return "Celebrations"
        case .paddleSkin:  return "Paddles"
        case .ballSkin:    return "Balls"
        case .title:       return "Titles"
        case .ability:     return "Abilities"
        }
    }
}

/// How a scored point is celebrated. The game owns one particle system, so
/// these are parameter sets for it rather than separate effects.
enum CelebrationStyle: String, CaseIterable, Equatable {
    case sparks, explosion, confetti, shockwave, fireworks
    case emberRain, starburst, pulse, rainbow, meteor
}

/// Single-player advantages. Only one is equipped at a time, so each is a
/// single clear change rather than a bundle.
enum Ability: String, CaseIterable, Equatable {
    case shieldStart      // begin with one free save
    case stickyStart      // begin able to catch and aim
    case widePaddle       // permanently wider paddle
    case slowServe        // the ball starts slower
    case steadyClimb      // it speeds up more gently
    case slowOpponent     // the AI paddle moves slower
    case calmOpponent     // the AI ramps up more slowly as you score
    case luckyDrops       // power-ups appear sooner
    case bigDrops         // power-ups are easier to catch
    case longCatch        // a caught ball can be held longer
}

/// One buyable thing. It carries its own effect so the catalog and the game
/// can't drift apart.
struct Unlockable: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let cost: Int
    let category: UnlockCategory
    var color: Color? = nil
    var celebration: CelebrationStyle? = nil
    var ability: Ability? = nil

    /// Abilities change how the game plays, so they are never applied in a
    /// match against another person — nobody should lose to someone else's
    /// grinding rather than their own play.
    var singlePlayerOnly: Bool { category == .ability }
}

enum UnlockCatalog {
    static let all: [Unlockable] = celebrations + paddles + balls + titles + abilities

    // MARK: - Celebrations

    private static let celebrations: [Unlockable] = [
        Unlockable(id: "celebration.sparks", name: "Sparks", detail: "The classic burst",
                   cost: 0, category: .celebration, celebration: .sparks),
        Unlockable(id: "celebration.explosion", name: "Explosion", detail: "A big orange blast",
                   cost: 40, category: .celebration, celebration: .explosion),
        Unlockable(id: "celebration.emberRain", name: "Ember Rain", detail: "Slow falling embers",
                   cost: 60, category: .celebration, celebration: .emberRain),
        Unlockable(id: "celebration.confetti", name: "Confetti", detail: "Colour everywhere",
                   cost: 75, category: .celebration, celebration: .confetti),
        Unlockable(id: "celebration.pulse", name: "Pulse", detail: "One clean ring",
                   cost: 90, category: .celebration, celebration: .pulse),
        Unlockable(id: "celebration.shockwave", name: "Shockwave", detail: "A ring that races out",
                   cost: 120, category: .celebration, celebration: .shockwave),
        Unlockable(id: "celebration.starburst", name: "Starburst", detail: "Spokes of light",
                   cost: 150, category: .celebration, celebration: .starburst),
        Unlockable(id: "celebration.meteor", name: "Meteor", detail: "A few heavy streaks",
                   cost: 180, category: .celebration, celebration: .meteor),
        Unlockable(id: "celebration.fireworks", name: "Fireworks", detail: "Fast and loud",
                   cost: 220, category: .celebration, celebration: .fireworks),
        Unlockable(id: "celebration.rainbow", name: "Rainbow", detail: "Every colour at once",
                   cost: 300, category: .celebration, celebration: .rainbow),
    ]

    // MARK: - Paddle skins

    private static let paddles: [Unlockable] = [
        Unlockable(id: "paddle.white", name: "Classic", detail: "Plain white",
                   cost: 0, category: .paddleSkin, color: .white),
        Unlockable(id: "paddle.sky", name: "Sky", detail: "Cool blue",
                   cost: 30, category: .paddleSkin, color: Color(red: 0.40, green: 0.75, blue: 1.00)),
        Unlockable(id: "paddle.gold", name: "Gold", detail: "For show-offs",
                   cost: 50, category: .paddleSkin, color: GameConstants.goldPaddle),
        Unlockable(id: "paddle.crimson", name: "Crimson", detail: "Deep red",
                   cost: 70, category: .paddleSkin, color: Color(red: 0.85, green: 0.18, blue: 0.25)),
        Unlockable(id: "paddle.neon", name: "Neon", detail: "Electric green",
                   cost: 90, category: .paddleSkin, color: GameConstants.neonPaddle),
        Unlockable(id: "paddle.violet", name: "Violet", detail: "Royal purple",
                   cost: 110, category: .paddleSkin, color: Color(red: 0.65, green: 0.40, blue: 1.00)),
        Unlockable(id: "paddle.mint", name: "Mint", detail: "Soft and cold",
                   cost: 130, category: .paddleSkin, color: Color(red: 0.55, green: 1.00, blue: 0.80)),
        Unlockable(id: "paddle.amber", name: "Amber", detail: "Warm orange",
                   cost: 160, category: .paddleSkin, color: Color(red: 1.00, green: 0.62, blue: 0.20)),
        Unlockable(id: "paddle.rose", name: "Rose", detail: "Hot pink",
                   cost: 200, category: .paddleSkin, color: Color(red: 1.00, green: 0.40, blue: 0.65)),
        Unlockable(id: "paddle.slate", name: "Slate", detail: "Understated grey",
                   cost: 250, category: .paddleSkin, color: Color(red: 0.62, green: 0.66, blue: 0.72)),
    ]

    // MARK: - Ball skins

    private static let balls: [Unlockable] = [
        Unlockable(id: "ball.white", name: "Classic", detail: "Plain white",
                   cost: 0, category: .ballSkin, color: .white),
        Unlockable(id: "ball.ice", name: "Ice", detail: "Cold blue",
                   cost: 40, category: .ballSkin, color: GameConstants.iceBall),
        Unlockable(id: "ball.ember", name: "Ember", detail: "Burns orange",
                   cost: 60, category: .ballSkin, color: GameConstants.emberBall),
        Unlockable(id: "ball.lime", name: "Lime", detail: "Sharp green",
                   cost: 80, category: .ballSkin, color: Color(red: 0.70, green: 1.00, blue: 0.25)),
        Unlockable(id: "ball.plasma", name: "Plasma", detail: "Magenta glow",
                   cost: 100, category: .ballSkin, color: Color(red: 1.00, green: 0.25, blue: 0.90)),
        Unlockable(id: "ball.sunburst", name: "Sunburst", detail: "Bright yellow",
                   cost: 120, category: .ballSkin, color: Color(red: 1.00, green: 0.90, blue: 0.20)),
        Unlockable(id: "ball.aqua", name: "Aqua", detail: "Sea green",
                   cost: 150, category: .ballSkin, color: Color(red: 0.25, green: 0.95, blue: 0.85)),
        Unlockable(id: "ball.bubblegum", name: "Bubblegum", detail: "Sweet pink",
                   cost: 180, category: .ballSkin, color: Color(red: 1.00, green: 0.62, blue: 0.78)),
        Unlockable(id: "ball.silver", name: "Silver", detail: "Polished metal",
                   cost: 220, category: .ballSkin, color: Color(red: 0.80, green: 0.83, blue: 0.88)),
        Unlockable(id: "ball.void", name: "Void", detail: "Barely there",
                   cost: 280, category: .ballSkin, color: Color(red: 0.45, green: 0.45, blue: 0.55)),
    ]

    // MARK: - Titles

    private static let titles: [Unlockable] = [
        Unlockable(id: "title.rookie", name: "Rookie", detail: "Everyone starts here", cost: 0, category: .title),
        Unlockable(id: "title.paddler", name: "Paddler", detail: "You've put the hours in", cost: 30, category: .title),
        Unlockable(id: "title.rallyking", name: "Rally King", detail: "Earned the hard way", cost: 100, category: .title),
        Unlockable(id: "title.wallbreaker", name: "Wallbreaker", detail: "Nothing gets past you", cost: 150, category: .title),
        Unlockable(id: "title.netninja", name: "Net Ninja", detail: "Quiet and quick", cost: 200, category: .title),
        Unlockable(id: "title.ace", name: "Ace", detail: "Hard to serve to", cost: 260, category: .title),
        Unlockable(id: "title.untouchable", name: "Untouchable", detail: "Still unbeaten", cost: 330, category: .title),
        Unlockable(id: "title.crownholder", name: "Crown Holder", detail: "Top of the pile", cost: 400, category: .title),
        Unlockable(id: "title.grandmaster", name: "Grandmaster", detail: "Few get here", cost: 550, category: .title),
        Unlockable(id: "title.legend", name: "Pong Legend", detail: "The last title", cost: 750, category: .title),
    ]

    // MARK: - Abilities (single player only)

    private static let abilities: [Unlockable] = [
        Unlockable(id: "ability.shieldStart", name: "Opening Shield", detail: "Start with one save",
                   cost: 80, category: .ability, ability: .shieldStart),
        Unlockable(id: "ability.slowServe", name: "Gentle Serve", detail: "The ball starts slower",
                   cost: 90, category: .ability, ability: .slowServe),
        Unlockable(id: "ability.widePaddle", name: "Long Paddle", detail: "A wider paddle, always",
                   cost: 110, category: .ability, ability: .widePaddle),
        Unlockable(id: "ability.bigDrops", name: "Big Drops", detail: "Power-ups are easier to catch",
                   cost: 120, category: .ability, ability: .bigDrops),
        Unlockable(id: "ability.luckyDrops", name: "Lucky Drops", detail: "Power-ups appear sooner",
                   cost: 140, category: .ability, ability: .luckyDrops),
        Unlockable(id: "ability.stickyStart", name: "Opening Catch", detail: "Start able to catch and aim",
                   cost: 160, category: .ability, ability: .stickyStart),
        Unlockable(id: "ability.longCatch", name: "Long Catch", detail: "Hold a caught ball longer",
                   cost: 180, category: .ability, ability: .longCatch),
        Unlockable(id: "ability.steadyClimb", name: "Steady Climb", detail: "Speed rises more gently",
                   cost: 220, category: .ability, ability: .steadyClimb),
        Unlockable(id: "ability.calmOpponent", name: "Cool Rival", detail: "The AI ramps up slower",
                   cost: 280, category: .ability, ability: .calmOpponent),
        Unlockable(id: "ability.slowOpponent", name: "Slow Rival", detail: "The AI paddle moves slower",
                   cost: 350, category: .ability, ability: .slowOpponent),
    ]

    static func item(id: String) -> Unlockable? { all.first { $0.id == id } }

    /// Free items are owned from the start, so every category has a default
    /// and the game never has to handle "nothing equipped".
    static var freeIDs: Set<String> { Set(all.filter { $0.cost == 0 }.map(\.id)) }
}
