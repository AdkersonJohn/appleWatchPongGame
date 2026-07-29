import XCTest
import CoreGraphics
@testable import PongWatch_Watch_App

final class GameSnapshotTests: XCTestCase {
    func test_gameSnapshotRoundtripsViaJSON() throws {
        let original = makeSnapshot(
            balls: [BallState(x: 0.42, y: 0.37, vx: -0.5, vy: 0.8)],
            hostPaddleX: 0.5,
            clientPaddleX: 0.6,
            hostScore: 2,
            clientScore: 3,
            clientPaddleHit: true,
            tickSeq: 1234
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_paddleInputRoundtripsViaJSON() throws {
        let original = PaddleInput(protoVersion: 1, paddleX: 0.73, tickSeq: 99)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PaddleInput.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_networkMessageEnvelopeCarriesSnapshot() throws {
        let snap = makeSnapshot(countdownRemaining: 3, tickSeq: 0)
        let msg = NetworkMessage.snapshot(snap)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(NetworkMessage.self, from: data)
        if case .snapshot(let s) = decoded {
            XCTAssertEqual(s, snap)
        } else {
            XCTFail("Expected .snapshot case")
        }
    }

    func test_scoreEventEncodesScorerRole() throws {
        let event = ScoreEvent(impactX: 0.37, scoredBy: .client)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ScoreEvent.self, from: data)
        XCTAssertEqual(decoded.scoredBy, .client)
        XCTAssertEqual(decoded.impactX, 0.37, accuracy: 1e-9)
    }

    func test_protocolVersionIsTwo() {
        XCTAssertEqual(GameConstants.multiplayerProtocolVersion, 2)
    }

    func test_snapshotWithPowerUpsRoundTripsThroughJSON() throws {
        let snap = makeSnapshot(
            balls: [BallState(x: 0.1, y: 0.2, vx: 0.3, vy: 0.4),
                    BallState(x: 0.5, y: 0.6, vx: -0.3, vy: -0.4)],
            hostEffects: EffectsState(wideRemaining: 7.5, hasShield: true, stickyArmed: false),
            clientEffects: EffectsState(wideRemaining: 0, hasShield: false, stickyArmed: true),
            pickup: PickupState(kind: .multiBall, x: 0.5, y: 0.42, driftSign: -1),
            pickupCollected: .client
        )
        let data = try JSONEncoder().encode(NetworkMessage.snapshot(snap))
        let decoded = try JSONDecoder().decode(NetworkMessage.self, from: data)
        XCTAssertEqual(decoded, .snapshot(snap))
    }

    func test_stickyReleaseMessageRoundTrips() throws {
        let data = try JSONEncoder().encode(NetworkMessage.stickyRelease)
        let decoded = try JSONDecoder().decode(NetworkMessage.self, from: data)
        XCTAssertEqual(decoded, .stickyRelease)
    }
}

// MARK: - Test helpers

private func makeSnapshot(
    phase: GamePhase = .playing,
    balls: [BallState] = [BallState(x: 0.5, y: 0.5, vx: 0, vy: 0)],
    hostPaddleX: CGFloat = 0.5,
    clientPaddleX: CGFloat = 0.5,
    hostScore: Int = 0,
    clientScore: Int = 0,
    countdownRemaining: Int? = nil,
    scoreEvent: ScoreEvent? = nil,
    hostPaddleHit: Bool = false,
    clientPaddleHit: Bool = false,
    hostEffects: EffectsState = EffectsState(wideRemaining: 0, hasShield: false, stickyArmed: false),
    clientEffects: EffectsState = EffectsState(wideRemaining: 0, hasShield: false, stickyArmed: false),
    pickup: PickupState? = nil,
    pickupCollected: PeerRole? = nil,
    tickSeq: UInt32 = 1
) -> GameSnapshot {
    GameSnapshot(protoVersion: GameConstants.multiplayerProtocolVersion, phase: phase,
                 balls: balls, hostPaddleX: hostPaddleX, clientPaddleX: clientPaddleX,
                 hostScore: hostScore, clientScore: clientScore,
                 countdownRemaining: countdownRemaining, scoreEvent: scoreEvent,
                 hostPaddleHit: hostPaddleHit, clientPaddleHit: clientPaddleHit,
                 hostEffects: hostEffects, clientEffects: clientEffects,
                 pickup: pickup, pickupCollected: pickupCollected, tickSeq: tickSeq)
}
