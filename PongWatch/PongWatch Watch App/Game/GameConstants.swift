import CoreGraphics

enum GameConstants {
    // Paddle dimensions as fractions of screen size
    static let paddleWidth: CGFloat = 0.20
    static let paddleHeight: CGFloat = 0.03

    // Vertical placement of paddles (as fraction from top/bottom)
    static let paddleMarginY: CGFloat = 0.05

    // Ball
    static let ballRadius: CGFloat = 0.02  // fraction of screen width

    // Speeds (normalized units per second)
    static let initialBallSpeed: CGFloat = 0.6
    static let maxBallSpeed: CGFloat = 1.8
    static let speedIncreasePerTier: CGFloat = 0.10  // 10% per tier
    static let hitsPerSpeedTier: Int = 5

    // AI paddle max horizontal speed (normalized units per second)
    static let aiMaxSpeed: CGFloat = 0.31
}
