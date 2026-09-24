import XCTest
@testable import PongWatch_Watch_App

final class ImpactSparkTests: XCTestCase {
    private func playingState() -> GameState {
        let state = GameState()
        state.phase = .playing
        state.countdownRemaining = nil
        return state
    }

    func test_paddleHitThrowsSparksBackIntoTheField() {
        let state = playingState()
        state.spawnImpactSparks(at: CGPoint(x: 0.5, y: 0.95), awayFrom: .bottom)
        XCTAssertEqual(state.particles.count, GameConstants.impactSparkCount)
        XCTAssertTrue(state.particles.allSatisfy { $0.velocity.dy < 0 },
                      "sparks off the bottom paddle must fly upward, not through it")
        XCTAssertTrue(state.particles.allSatisfy { $0.red == 1 && $0.green == 1 && $0.blue == 1 },
                      "impact sparks are white; the coloured burst is for scoring")
    }

    func test_topPaddleSparksFlyDownward() {
        let state = playingState()
        state.spawnImpactSparks(at: CGPoint(x: 0.4, y: 0.05), awayFrom: .top)
        XCTAssertTrue(state.particles.allSatisfy { $0.velocity.dy > 0 })
    }

    /// Sparks are a flash, not a trail — they must clear well before the next
    /// rally so they never accumulate into a smear on a 40mm screen.
    func test_sparksExpireQuickly() {
        let state = playingState()
        state.spawnImpactSparks(at: CGPoint(x: 0.5, y: 0.95), awayFrom: .bottom)
        state.updateParticles(dt: GameConstants.impactSparkMaxLifespan + 0.01)
        XCTAssertTrue(state.particles.isEmpty)
    }

    /// A wall bounce during a real rally must leave sparks at the wall.
    func test_ballBouncingOffAWallSparks() {
        let state = playingState()
        state.ball = Ball(position: CGPoint(x: GameConstants.ballRadius * 0.5, y: 0.5),
                          velocity: CGVector(dx: -0.5, dy: 0))
        state.update(dt: 0.05)
        XCTAssertFalse(state.particles.isEmpty, "a wall bounce should show an impact")
        XCTAssertTrue(state.particles.allSatisfy { $0.velocity.dx > 0 },
                      "sparks off the left wall fly right")
    }

    func test_paddleBounceDuringPlaySparks() {
        let state = playingState()
        state.playerPaddleX = 0.5
        let paddleY = 1.0 - GameConstants.paddleMarginY
        state.ball = Ball(position: CGPoint(x: 0.5, y: paddleY - GameConstants.paddleHeight),
                          velocity: CGVector(dx: 0, dy: 0.5))
        state.update(dt: 0.05)
        XCTAssertFalse(state.particles.isEmpty, "a paddle hit should show an impact")
    }
}

final class MultiplayerSparkTests: XCTestCase {
    /// The client renders the host's physics, so without this the player on
    /// the client sees a ball change direction with no impact at all.
    @MainActor
    func test_clientSparksOnItsOwnPaddleHitFromTheSnapshot() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 100_000_000)
        fake.simulateIncoming(.snapshot(makeSnapshot(clientPaddleHit: true)))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(state.game.particles.isEmpty, "client's own paddle hit should spark")
    }

    @MainActor
    func test_clientSparksOnAWallImpactReportedByTheHost() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let impact = WallImpact(x: GameConstants.ballRadius, y: 0.4, onLeft: true)
        fake.simulateIncoming(.snapshot(makeSnapshot(wallImpact: impact)))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(state.game.particles.isEmpty, "a wall bounce must spark on both screens")
        XCTAssertTrue(state.game.particles.allSatisfy { $0.velocity.dx > 0 },
                      "sparks off the left wall fly right on the client too")
    }

    private func makeSnapshot(clientPaddleHit: Bool = false,
                              wallImpact: WallImpact? = nil) -> GameSnapshot {
        GameSnapshot(
            protoVersion: GameConstants.multiplayerProtocolVersion,
            phase: .playing,
            balls: [BallState(x: 0.5, y: 0.9, vx: 0, vy: -0.5)],
            hostPaddleX: 0.5, clientPaddleX: 0.5,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: clientPaddleHit,
            hostEffects: EffectsState(wideRemaining: 0, hasShield: false, stickyArmed: false),
            clientEffects: EffectsState(wideRemaining: 0, hasShield: false, stickyArmed: false),
            pickup: nil, pickupCollected: nil, stuckSide: nil, tickSeq: 1,
            wallImpact: wallImpact)
    }
}
