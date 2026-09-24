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
    /// Sent by both sides as soon as the link is up: "watch" or "phone".
    /// The host needs the client's platform to choose the field shape.
    case hello(platform: String)
    /// Host → client just before `.startMatch`: the agreed playfield
    /// width/height. Both sides scale their physics to it.
    case fieldShape(aspect: CGFloat)
    /// Client → host: the client tapped its screen to release a stuck ball.
    /// Host validates (no-op unless the client's side actually holds one).
    case stickyRelease
}

/// Guards against two devices running different builds, which is the likeliest
/// way a watch-to-phone match fails: the link connects and then nothing moves.
enum ProtoCheck {
    static func isCompatible(_ theirs: UInt8,
                             ours: UInt8 = GameConstants.multiplayerProtocolVersion) -> Bool {
        theirs == ours
    }
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
    /// Which side (if any) currently holds a stuck ball. nil when no ball is held.
    var stuckSide: PeerRole?
    /// Monotonic tick sequence; receiver discards out-of-order snapshots.
    var tickSeq: UInt32
    /// Non-nil for exactly one snapshot after the ball hit a side wall.
    var wallImpact: WallImpact? = nil
    /// The serve the host has queued during a countdown, in host space, so the
    /// client can draw the same preview instead of guessing.
    var pendingServeVX: CGFloat? = nil
    var pendingServeVY: CGFloat? = nil
}

/// Client → host at 30Hz; reports the client's crown-controlled paddle position.
struct PaddleInput: Codable, Equatable {
    var protoVersion: UInt8
    /// Paddle X in normalized [0, 1] space. X is symmetric across the flip
    /// so no coordinate transform is needed.
    var paddleX: CGFloat
    var tickSeq: UInt32
}

/// Where the ball met a side wall on the host's tick. The client can't derive
/// this — it renders the host's physics — so without it a wall bounce shows an
/// impact on one screen and nothing on the other.
struct WallImpact: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var onLeft: Bool
}

struct ScoreEvent: Codable, Equatable {
    var impactX: CGFloat
    var scoredBy: PeerRole
}

/// Picks the playfield shape a cross-device match is played on.
///
/// The two devices must agree, because the host simulates physics in
/// normalized coordinates and the client renders them. A watch in the match
/// forces the watch's shape: a tall phone field squeezed onto a watch is
/// unplayable, while a phone can letterbox the watch's shape perfectly well.
enum FieldShape {
    static func agreed(hostIsWatch: Bool, clientIsWatch: Bool, hostAspect: CGFloat) -> CGFloat {
        (hostIsWatch || clientIsWatch) ? GameConstants.watchPlayfieldAspect : hostAspect
    }

    /// Converts an agreed width/height into the factor that keeps height-based
    /// sizes looking the same as they do on the watch.
    static func verticalScale(forAspect aspect: CGFloat) -> CGFloat {
        aspect / GameConstants.watchPlayfieldAspect
    }
}
