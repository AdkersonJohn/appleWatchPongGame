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
