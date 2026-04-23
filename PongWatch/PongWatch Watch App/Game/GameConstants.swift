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

    // Countdown shown before each new ball launch (3…2…1 then go)
    static let countdownStart: Int = 3

    // Scoring burst
    static let particlesPerBurst: Int = 20
    static let particleMinSpeed: CGFloat = 0.4
    static let particleMaxSpeed: CGFloat = 1.2
    static let particleMinLifespan: CGFloat = 0.4
    static let particleMaxLifespan: CGFloat = 0.8
    static let particleRadiusFactor: CGFloat = 0.4   // fraction of ballRadius

    // Warm palette: gold, orange, red-orange, yellow. Each entry is (r, g, b) in 0…1.
    static let particlePalette: [(CGFloat, CGFloat, CGFloat)] = [
        (1.00, 0.843, 0.000),   // gold     #FFD700
        (1.00, 0.549, 0.000),   // orange   #FF8C00
        (1.00, 0.271, 0.000),   // red-orange #FF4500
        (1.00, 0.918, 0.000)    // yellow   #FFEA00
    ]

    // MARK: - Multiplayer

    /// Match ends when a player reaches this score.
    static let multiplayerWinningScore: Int = 5

    /// Host → client snapshot rate (Hz).
    static let snapshotHz: Double = 30

    /// Client → host paddle-input rate (Hz).
    static let paddleInputHz: Double = 30

    /// Seconds of wrist-down grace before forfeiting a multiplayer match.
    static let multiplayerGraceSeconds: Double = 3.0

    /// MultipeerConnectivity service type. 1–15 chars, lowercase ASCII + hyphens.
    static let mcServiceType: String = "pongwatch"

    /// Protocol version included in every MP message. Bump when the wire format changes.
    static let multiplayerProtocolVersion: UInt8 = 1
}
