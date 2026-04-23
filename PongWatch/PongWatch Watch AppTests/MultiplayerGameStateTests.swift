import XCTest
import Network
@testable import PongWatch_Watch_App

final class MultiplayerGameStateTests: XCTestCase {
    func test_initialStateIsIdle() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        XCTAssertEqual(state.matchPhase, .pairing)
        XCTAssertEqual(state.hostScore, 0)
        XCTAssertEqual(state.clientScore, 0)
        XCTAssertNil(state.role)
    }

    func test_onConnectAsHostTransitionsToPlaying() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .host)
        XCTAssertEqual(state.matchPhase, .playing)
    }

    func test_onConnectAsClientTransitionsToPlaying() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .client)
        XCTAssertEqual(state.matchPhase, .playing)
    }

    func test_hostTickSendsSnapshot() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        state.tickIfHost(dt: 1.0 / 30.0)
        let snapshotSends = fake.sentMessages.compactMap { msg -> GameSnapshot? in
            if case .snapshot(let s) = msg.message { return s } else { return nil }
        }
        XCTAssertEqual(snapshotSends.count, 1)
        XCTAssertEqual(snapshotSends[0].protoVersion, GameConstants.multiplayerProtocolVersion)
    }

    func test_hostTickAdvancesInnerGame() {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        game.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                         velocity: CGVector(dx: 0.5, dy: 0.5))
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        let startX = game.ball.position.x
        state.tickIfHost(dt: 0.1)
        XCTAssertNotEqual(game.ball.position.x, startX)
    }

    func test_clientTickDoesNotSendSnapshots() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        state.tickIfHost(dt: 1.0 / 30.0)
        let snapshotSends = fake.sentMessages.filter {
            if case .snapshot = $0.message { return true } else { return false }
        }
        XCTAssertTrue(snapshotSends.isEmpty)
    }

    func test_clientFlipsBallYOnIncomingSnapshot() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.3, ballY: 0.2, ballVX: 0, ballVY: 0.5,
            hostPaddleX: 0.4, clientPaddleX: 0.6,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Client sees itself at the bottom → flip y.
        XCTAssertEqual(state.game.ball.position.y, 0.8, accuracy: 1e-6)   // 1.0 - 0.2
        XCTAssertEqual(state.game.ball.position.x, 0.3, accuracy: 1e-6)   // x unchanged
        // Velocity Y is flipped too.
        XCTAssertEqual(state.game.ball.velocity.dy, -0.5, accuracy: 1e-6)
    }

    func test_clientPaddleAssignmentFlipped() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.5, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.4,
            clientPaddleX: 0.6,
            hostScore: 1, clientScore: 2,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        // "My" paddle uses local prediction only; snapshot clientPaddleX is ignored.
        XCTAssertEqual(state.game.playerPaddleX, 0.5, accuracy: 1e-6)  // unchanged default
        XCTAssertEqual(state.game.aiPaddleX, 0.4, accuracy: 1e-6)
    }

    func test_clientIgnoresOutOfOrderSnapshots() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let newerSnap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.7, ballY: 0.3, ballVX: 0, ballVY: 0,
            hostPaddleX: 0, clientPaddleX: 0,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 10
        )
        let olderSnap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.1, ballY: 0.9, ballVX: 0, ballVY: 0,
            hostPaddleX: 0, clientPaddleX: 0,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 5
        )
        fake.simulateIncoming(.snapshot(newerSnap))
        try? await Task.sleep(nanoseconds: 30_000_000)
        fake.simulateIncoming(.snapshot(olderSnap))
        try? await Task.sleep(nanoseconds: 30_000_000)
        // Newer snapshot's ball position should still apply.
        XCTAssertEqual(state.game.ball.position.x, 0.7, accuracy: 1e-6)
    }

    func test_clientSendsPaddleInputOnCrown() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        state.setLocalPaddle(normalizedCrown: 0.72)
        let inputs: [PaddleInput] = fake.sentMessages.compactMap {
            if case .paddleInput(let p) = $0.message { return p } else { return nil }
        }
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].paddleX, 0.72, accuracy: 1e-6)
    }

    func test_hostAppliesIncomingPaddleInput() async {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        let input = PaddleInput(protoVersion: 1, paddleX: 0.83, tickSeq: 1)
        fake.simulateIncoming(.paddleInput(input))
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Host stores the client paddle into the inner GameState's aiPaddleX slot
        // (which represents the top paddle in host-coord physics).
        XCTAssertEqual(game.aiPaddleX, 0.83, accuracy: 1e-6)
    }

    func test_hostIgnoresOutOfOrderPaddleInput() async {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        let newer = PaddleInput(protoVersion: 1, paddleX: 0.83, tickSeq: 5)
        let older = PaddleInput(protoVersion: 1, paddleX: 0.10, tickSeq: 3)
        fake.simulateIncoming(.paddleInput(newer))
        try? await Task.sleep(nanoseconds: 30_000_000)
        fake.simulateIncoming(.paddleInput(older))
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(game.aiPaddleX, 0.83, accuracy: 1e-6)
    }

    func test_clientSnapshotDoesNotOverwriteLocallyPredictedPaddle() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        // Local crown input sets our predicted paddle.
        state.setLocalPaddle(normalizedCrown: 0.42)
        // Now a snapshot arrives with a stale clientPaddleX.
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.5, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.15,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Our local prediction wins.
        XCTAssertEqual(state.game.playerPaddleX, 0.42, accuracy: 1e-6)
        // Opponent still trusts the snapshot.
        XCTAssertEqual(state.game.aiPaddleX, 0.5, accuracy: 1e-6)
    }

    func test_hostScoreEventWhenBallExitsTop() {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        // Ball near top with upward velocity → will exit on next step.
        game.ball = Ball(position: CGPoint(x: 0.3, y: 0.01),
                         velocity: CGVector(dx: 0, dy: -1.0))
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        state.tickIfHost(dt: 0.1)
        let scoringSnap = fake.sentMessages.compactMap { msg -> GameSnapshot? in
            if case .snapshot(let s) = msg.message, s.scoreEvent != nil { return s } else { return nil }
        }.first
        XCTAssertNotNil(scoringSnap)
        XCTAssertEqual(scoringSnap?.scoreEvent?.scoredBy, .host)
        XCTAssertEqual(state.hostScore, 1)
    }

    func test_clientSpawnsParticlesWhenTheyAreTheScorer() async {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.0, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.5,
            hostScore: 0, clientScore: 1,
            countdownRemaining: 3,
            scoreEvent: ScoreEvent(impactX: 0.37, scoredBy: .client),
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.game.particles.count, GameConstants.particlesPerBurst)
    }

    func test_clientDoesNotSpawnParticlesWhenHostScores() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.0, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.5,
            hostScore: 1, clientScore: 0,
            countdownRemaining: 3,
            scoreEvent: ScoreEvent(impactX: 0.37, scoredBy: .host),
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(state.game.particles.isEmpty)
    }
}
