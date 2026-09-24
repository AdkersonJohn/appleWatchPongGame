import Foundation
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

/// One buyable thing. `effect` is what the game reads once it's equipped.
struct Unlockable: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let cost: Int
    let category: UnlockCategory

    /// Abilities change how the game plays, so they are never applied in a
    /// match against another person — nobody should lose to someone else's
    /// grinding rather than their own play.
    var singlePlayerOnly: Bool { category == .ability }
}

enum UnlockCatalog {
    static let all: [Unlockable] = [
        // Celebrations — the payoff for scoring, drawn with the particle system.
        Unlockable(id: "celebration.sparks", name: "Sparks", detail: "The classic burst", cost: 0, category: .celebration),
        Unlockable(id: "celebration.explosion", name: "Explosion", detail: "A big orange blast", cost: 40, category: .celebration),
        Unlockable(id: "celebration.confetti", name: "Confetti", detail: "Colour everywhere", cost: 75, category: .celebration),
        Unlockable(id: "celebration.shockwave", name: "Shockwave", detail: "A ring that races out", cost: 120, category: .celebration),

        // Paddle skins.
        Unlockable(id: "paddle.white", name: "Classic", detail: "Plain white", cost: 0, category: .paddleSkin),
        Unlockable(id: "paddle.gold", name: "Gold", detail: "For show-offs", cost: 50, category: .paddleSkin),
        Unlockable(id: "paddle.neon", name: "Neon", detail: "Electric green", cost: 90, category: .paddleSkin),

        // Ball skins.
        Unlockable(id: "ball.white", name: "Classic", detail: "Plain white", cost: 0, category: .ballSkin),
        Unlockable(id: "ball.ember", name: "Ember", detail: "Burns orange", cost: 60, category: .ballSkin),
        Unlockable(id: "ball.ice", name: "Ice", detail: "Cold blue", cost: 60, category: .ballSkin),

        // Titles, shown beside your name in the lobby.
        Unlockable(id: "title.rookie", name: "Rookie", detail: "Everyone starts here", cost: 0, category: .title),
        Unlockable(id: "title.rallyking", name: "Rally King", detail: "Earned the hard way", cost: 100, category: .title),
        Unlockable(id: "title.wallbreaker", name: "Wallbreaker", detail: "Nothing gets past you", cost: 150, category: .title),

        // Abilities — single player only.
        Unlockable(id: "ability.shieldStart", name: "Opening Shield", detail: "Start with one save", cost: 80, category: .ability),
        Unlockable(id: "ability.widePaddle", name: "Long Paddle", detail: "A wider paddle, always", cost: 110, category: .ability),
        Unlockable(id: "ability.luckyDrops", name: "Lucky Drops", detail: "Power-ups appear sooner", cost: 140, category: .ability),
    ]

    static func item(id: String) -> Unlockable? { all.first { $0.id == id } }

    /// Free items are owned from the start, so every category has a default
    /// and the game never has to handle "nothing equipped".
    static var freeIDs: Set<String> { Set(all.filter { $0.cost == 0 }.map(\.id)) }
}
