import CoreGraphics

struct Ball: Equatable {
    var position: CGPoint
    var velocity: CGVector
}

enum GamePhase: Equatable {
    case start
    case playing
    case gameOver
}

struct Particle: Equatable {
    var position: CGPoint       // normalized 0…1 in both axes
    var velocity: CGVector      // normalized units per second
    var ageRemaining: CGFloat   // seconds until removal
    var totalAge: CGFloat       // original lifespan (for alpha fade)
    var radius: CGFloat         // normalized fraction of screen width
    var red: CGFloat            // 0…1
    var green: CGFloat
    var blue: CGFloat
}
