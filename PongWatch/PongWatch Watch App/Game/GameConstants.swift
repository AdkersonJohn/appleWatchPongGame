import CoreGraphics
import SwiftUI

enum GameConstants {
    // Paddle dimensions as fractions of screen size
    static let paddleWidth: CGFloat = 0.20
    /// Fraction of field height, so it shrinks with `verticalScale` to keep the
    /// paddle's on-screen thickness the same on a tall iPhone field.
    static var paddleHeight: CGFloat { 0.03 * verticalScale }

    /// Field shape relative to the watch screen: (width/height) ÷ watch
    /// (width/height). 1 on the watch, about 0.55 on a tall iPhone. Everything
    /// measured as a fraction of field *height* multiplies by this so sizes and
    /// hitboxes look the same as on the watch; speeds stay normalized, so a
    /// rally takes the same time on both.
    // ponytail: process-wide, set once by the iPhone GameView; make it
    // per-GameState if two differently shaped fields ever run at once.
    static var verticalScale: CGFloat = 1

    // Width/height of the 46mm watch screen the physics were tuned on.
    static let watchPlayfieldAspect: CGFloat = 416.0 / 496.0

    /// Seconds to wait for an invited peer's connection before giving up. Long
    /// enough for a slow peer-to-peer link to come up, short enough that a dead
    /// one doesn't look like a hung app.
    static let inviteTimeoutSeconds: Double = 20

    // Vertical placement of paddles (as fraction from top/bottom)
    static let paddleMarginY: CGFloat = 0.05

    // Ball
    static let ballRadius: CGFloat = 0.02  // fraction of screen width
    /// The ball radius expressed as a fraction of field height, for vertical hit tests.
    static var ballRadiusY: CGFloat { ballRadius * verticalScale }

    // Speeds (normalized units per second)
    static let initialBallSpeed: CGFloat = 0.6
    static let maxBallSpeed: CGFloat = 1.8
    static let speedIncreasePerTier: CGFloat = 0.10  // 10% per tier
    static let hitsPerSpeedTier: Int = 5

    // AI paddle max horizontal speed (normalized units per second)
    static let aiMaxSpeed: CGFloat = 0.31

    // Every point scored against the AI makes it react faster, by this fraction
    // of its base speed, until it tops out at `aiSpeedFactorCap` × base — the
    // cap is what keeps a long run from turning into an unbeatable wall.
    // ponytail: linear ramp; swap for a curve if the late game feels off.
    static let aiSpeedIncreasePerPoint: CGFloat = 0.06
    static let aiSpeedFactorCap: CGFloat = 2.0

    /// AI paddle speed after the player has scored `playerScore` times.
    static func aiSpeed(playerScore: Int) -> CGFloat {
        let factor = min(aiSpeedFactorCap,
                         1 + aiSpeedIncreasePerPoint * CGFloat(max(0, playerScore)))
        return aiMaxSpeed * factor
    }

    // Countdown shown before each new ball launch (3…2…1 then go)
    static let countdownStart: Int = 3

    // Digital Crown. Velocity arrives in rotations/second, so one full crown
    // turn sweeps `crownWidthPerRotation` of the screen. The speed cap is a
    // safety rail against a runaway velocity reading, not a normal limit; the
    // staleness window stops the paddle if onIdle is late.
    // ponytail: feel-tune on hardware.
    static let crownWidthPerRotation: CGFloat = 1.0
    static let crownMaxPaddleSpeed: CGFloat = 2.5
    static let crownVelocityStaleAfter: Double = 0.12
    // One tick per this much paddle travel; min interval caps fast-spin tick
    // rate at ~7/s — skin stops resolving individual taps past ~8-10 Hz, so a
    // higher cap reads as buzz even though the clicks are mechanically spaced.
    static let crownHapticStep: CGFloat = 0.10
    static let crownHapticMinInterval: Double = 0.14

    /// Length of the serve-direction preview, as a fraction of field height.
    /// Long enough to read at a glance, short enough not to reach a paddle and
    /// look like it's predicting the whole rally.
    static let servePreviewLength: CGFloat = 0.22
    /// Gap before the dashes start, so they clear the countdown digit drawn
    /// in the middle of the field rather than running through it.
    static let servePreviewInset: CGFloat = 0.10

    // Unlockable skin colours, kept here so the catalog and the renderer can't
    // drift apart.
    static let goldPaddle = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let neonPaddle = Color(red: 0.30, green: 1.00, blue: 0.45)
    static let emberBall = Color(red: 1.00, green: 0.50, blue: 0.15)
    static let iceBall = Color(red: 0.55, green: 0.85, blue: 1.00)
    /// How much wider the Long Paddle ability makes the player's paddle.
    static let longPaddleFactor: CGFloat = 1.25
    /// Lucky Drops shortens the wait between power-ups by this factor.
    static let luckyDropsFactor: CGFloat = 0.6

    // Impact sparks — the small white flash where the ball meets a paddle or
    // wall. Deliberately fewer, smaller and shorter-lived than the scoring
    // burst: this fires several times a rally, so it has to read as a tick of
    // feedback rather than a firework.
    static let impactSparkCount: Int = 5
    static let impactSparkMinSpeed: CGFloat = 0.25
    static let impactSparkMaxSpeed: CGFloat = 0.65
    static let impactSparkMinLifespan: CGFloat = 0.10
    static let impactSparkMaxLifespan: CGFloat = 0.22
    /// Fraction of ballRadius. Smaller than the scoring burst's specks.
    static let impactSparkRadiusFactor: CGFloat = 0.30
    /// Half-angle of the spray cone around the surface normal. A wide fan
    /// looks like an explosion; this keeps it hugging the surface.
    static let impactSparkSpread: CGFloat = .pi / 3

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

    /// If no message arrives from the peer for this long, assume the peer is
    /// gone and end the match locally. Longer than `multiplayerGraceSeconds`
    /// so it doesn't false-fire during a legitimate wrist-down pause.
    static let peerSilenceTimeoutSeconds: Double = 5.0

    /// MultipeerConnectivity service type. 1–15 chars, lowercase ASCII + hyphens.
    static let mcServiceType: String = "pongwatch"

    /// Protocol version included in every MP message. Bump when the wire format changes.
    static let multiplayerProtocolVersion: UInt8 = 3

    // MARK: - Power-ups

    static let powerUpSpawnIntervalMin: CGFloat = 12
    static let powerUpSpawnIntervalMax: CGFloat = 20
    /// Pickup drift speed, normalized units per second.
    static let powerUpDriftSpeed: CGFloat = 0.08
    /// Pickup radius = 1.5 × ballRadius.
    static let powerUpPickupRadius: CGFloat = 0.03
    static var powerUpPickupRadiusY: CGFloat { powerUpPickupRadius * verticalScale }
    static let widePaddleFactor: CGFloat = 1.5
    static let widePaddleDuration: CGFloat = 10
    static let stickyHoldSeconds: CGFloat = 3
    static let aiStickyHoldSeconds: CGFloat = 1
    static let multiBallCount: Int = 3
    static let multiBallSplitAngle: CGFloat = .pi / 9   // 20°

    static func pickupColor(for kind: PowerUpKind) -> (CGFloat, CGFloat, CGFloat) {
        switch kind {
        case .widePaddle: return (1.00, 0.843, 0.000)   // gold
        case .shield:     return (0.25, 0.55, 1.00)     // blue
        case .stickyBall: return (0.30, 0.85, 0.40)     // green
        case .multiBall:  return (1.00, 0.549, 0.000)   // orange
        }
    }

    static func pickupSymbol(for kind: PowerUpKind) -> String {
        switch kind {
        case .widePaddle: return "arrow.left.and.right"
        case .shield:     return "shield.fill"
        case .stickyBall: return "hand.raised.fill"
        case .multiBall:  return "3.circle.fill"
        }
    }
}
