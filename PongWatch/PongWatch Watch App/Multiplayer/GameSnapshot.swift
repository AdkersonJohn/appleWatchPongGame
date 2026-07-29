import Foundation
import CoreGraphics

/// Envelope for any message sent over the MC session. Using an enum ensures
/// exhaustive handling on the receiver and gives us a stable tag in JSON.
enum NetworkMessage: Codable, Equatable {
    case snapshot(GameSnapshot)
    case paddleInput(PaddleInput)
    case rematchRequest
    case endMatch
    case paused(role: PeerRole)
    case resumed(role: PeerRole)
    case forfeit(by: PeerRole)
    /// Host → client after the host picks a target score. nil = no win condition.
    case startMatch(winningScore: Int?)
    /// Client → host immediately after the client taps Accept. The host stays
    /// on its waiting view until this arrives so the score picker can't open
    /// while the invite is still pending.
    case clientReady
    /// Client → host: the client tapped its screen to release a stuck ball.
    /// Host validates (no-op unless the client's side actually holds one).
    case stickyRelease
}

struct BallState: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
}

struct PickupState: Codable, Equatable {
    var kind: PowerUpKind
    var x: CGFloat
    var y: CGFloat
    var driftSign: CGFloat
}

struct EffectsState: Codable, Equatable {
    var wideRemaining: CGFloat
    var hasShield: Bool
    var stickyArmed: Bool
}

/// Full game state snapshot from host → client at 30Hz.
/// All coordinates are in HOST coordinate space (host at bottom, y grows downward).
/// Client must flip Y on render.
struct GameSnapshot: Codable, Equatable {
    var protoVersion: UInt8
    var phase: GamePhase
    /// All live balls in HOST coordinate space. Client flips Y on render.
    var balls: [BallState]
    var hostPaddleX: CGFloat
    var clientPaddleX: CGFloat
    var hostScore: Int
    var clientScore: Int
    /// nil when ball is in play; otherwise 3/2/1.
    var countdownRemaining: Int?
    /// Non-nil for exactly one snapshot after a scoring event.
    var scoreEvent: ScoreEvent?
    /// True for one snapshot on the tick host's paddle collided with the ball.
    var hostPaddleHit: Bool
    /// True for one snapshot on the tick client's paddle collided.
    var clientPaddleHit: Bool
    var hostEffects: EffectsState
    var clientEffects: EffectsState
    var pickup: PickupState?
    /// Non-nil for exactly one snapshot after a pickup is collected.
    var pickupCollected: PeerRole?
    /// Monotonic tick sequence; receiver discards out-of-order snapshots.
    var tickSeq: UInt32
}

/// Client → host at 30Hz; reports the client's crown-controlled paddle position.
struct PaddleInput: Codable, Equatable {
    var protoVersion: UInt8
    /// Paddle X in normalized [0, 1] space. X is symmetric across the flip
    /// so no coordinate transform is needed.
    var paddleX: CGFloat
    var tickSeq: UInt32
}

struct ScoreEvent: Codable, Equatable {
    var impactX: CGFloat
    var scoredBy: PeerRole
}
