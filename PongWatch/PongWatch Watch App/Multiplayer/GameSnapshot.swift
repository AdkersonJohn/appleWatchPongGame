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
}

/// Full game state snapshot from host → client at 30Hz.
/// All coordinates are in HOST coordinate space (host at bottom, y grows downward).
/// Client must flip Y on render.
struct GameSnapshot: Codable, Equatable {
    var protoVersion: UInt8
    var phase: GamePhase
    var ballX: CGFloat
    var ballY: CGFloat
    var ballVX: CGFloat
    var ballVY: CGFloat
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
