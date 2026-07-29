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

    func test_onConnectAsHostTransitionsToWaitingForOpponentAccept() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .host)
        XCTAssertEqual(state.matchPhase, .waitingForOpponentAccept)
    }

    func test_onConnectAsClientTransitionsToConfiguringMatchAndSendsClientReady() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .client)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
        let clientReadySends = fake.sentMessages.filter {
            if case .clientReady = $0.message { return true } else { return false }
        }
        XCTAssertEqual(clientReadySends.count, 1)
    }

    func test_hostTickSendsSnapshot() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        state.tick(dt: 1.0 / 30.0)
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
        state.tick(dt: 0.1)
        XCTAssertNotEqual(game.ball.position.x, startX)
    }

    func test_clientTickDoesNotSendSnapshots() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        state.tick(dt: 1.0 / 30.0)
        let snapshotSends = fake.sentMessages.filter {
            if case .snapshot = $0.message { return true } else { return false }
        }
        XCTAssertTrue(snapshotSends.isEmpty)
    }

    func test_clientFlipsBallYOnIncomingSnapshot() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let snap = makeSnapshot(
            balls: [BallState(x: 0.3, y: 0.2, vx: 0, vy: 0.5)],
            hostPaddleX: 0.4, clientPaddleX: 0.6
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
        let snap = makeSnapshot(
            hostPaddleX: 0.4, clientPaddleX: 0.6,
            hostScore: 1, clientScore: 2
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
        let newerSnap = makeSnapshot(
            balls: [BallState(x: 0.7, y: 0.3, vx: 0, vy: 0)],
            hostPaddleX: 0, clientPaddleX: 0,
            tickSeq: 10
        )
        let olderSnap = makeSnapshot(
            balls: [BallState(x: 0.1, y: 0.9, vx: 0, vy: 0)],
            hostPaddleX: 0, clientPaddleX: 0,
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
        let snap = makeSnapshot(hostPaddleX: 0.5, clientPaddleX: 0.15)
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
        state.tick(dt: 0.1)
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
        let snap = makeSnapshot(
            balls: [BallState(x: 0.5, y: 0.0, vx: 0, vy: 0)],
            hostScore: 0, clientScore: 1,
            countdownRemaining: 3,
            scoreEvent: ScoreEvent(impactX: 0.37, scoredBy: .client)
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.game.particles.count, GameConstants.particlesPerBurst)
    }

    func test_clientDoesNotSpawnParticlesWhenHostScores() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let snap = makeSnapshot(
            balls: [BallState(x: 0.5, y: 0.0, vx: 0, vy: 0)],
            hostScore: 1, clientScore: 0,
            countdownRemaining: 3,
            scoreEvent: ScoreEvent(impactX: 0.37, scoredBy: .host)
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(state.game.particles.isEmpty)
    }

    func test_clientPlaysHapticOnClientPaddleHitFlag() async {
        let fake = FakeMultiplayerService()
        let game = GameState(highScoreStore: HighScoreStore(), hapticPlayer: RecordingHapticPlayer())
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .client)
        let snap = makeSnapshot(clientPaddleHit: true)
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        let haptic = game.injectedHapticPlayerForTests as! RecordingHapticPlayer
        XCTAssertEqual(haptic.clickCount, 1)
    }

    func test_wristDownUnderGracePeriodDoesNotForfeit() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { state.startMatch(winningScore: 5) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.onScenePhaseChanged(to: .inactive)
        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        state.onScenePhaseChanged(to: .active)
        try? await Task.sleep(nanoseconds: 100_000_000)
        if case .playing = state.matchPhase {} else { XCTFail("Expected .playing, got \(state.matchPhase)") }
    }

    func test_wristDownOverGracePeriodForfeits() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { state.startMatch(winningScore: 5) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.setGraceSecondsForTests(0.05)
        state.onScenePhaseChanged(to: .inactive)
        try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s exceeds 0.05s grace
        if case .matchOver(let winner) = state.matchPhase {
            XCTAssertEqual(winner, .client)  // host forfeited → client wins
        } else {
            XCTFail("Expected .matchOver, got \(state.matchPhase)")
        }
    }

    func test_wristDownSendsPausedMessage() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { state.startMatch(winningScore: 5) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.onScenePhaseChanged(to: .inactive)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let pausedSends = fake.sentMessages.filter {
            if case .paused = $0.message { return true } else { return false }
        }
        XCTAssertEqual(pausedSends.count, 1)
    }

    func test_requestRematchAsHostSendsAndResets() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)
        state.requestRematch()
        let rematchSends = fake.sentMessages.filter {
            if case .rematchRequest = $0.message { return true } else { return false }
        }
        XCTAssertEqual(rematchSends.count, 1)
        XCTAssertEqual(state.hostScore, 0)
        XCTAssertEqual(state.clientScore, 0)
        if case .playing = state.matchPhase {} else { XCTFail("Expected .playing") }
    }

    func test_clientReceivingRematchResetsScoresAndPlays() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 100_000_000)
        fake.simulateIncoming(.rematchRequest)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.hostScore, 0)
        XCTAssertEqual(state.clientScore, 0)
        if case .playing = state.matchPhase {} else { XCTFail("Expected .playing") }
    }

    func test_leaveMatchTearsDownSession() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)
        state.leaveMatch()
        XCTAssertEqual(fake.connectionState, .idle)
    }

    func test_disconnectMidMatchEndsWithLocalWin() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { state.startMatch(winningScore: 5) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateDisconnect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        if case .matchOver(let winner) = state.matchPhase {
            XCTAssertEqual(winner, .host)
        } else {
            XCTFail("Expected .matchOver(winner: .host), got \(state.matchPhase)")
        }
    }

    func test_clientTransitionsToMatchOverWhenSnapshotShowsWinningScore() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.startMatch(winningScore: 5))
        try? await Task.sleep(nanoseconds: 50_000_000)
        let snap = makeSnapshot(
            hostScore: GameConstants.multiplayerWinningScore, clientScore: 3
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        if case .matchOver(let winner) = state.matchPhase {
            XCTAssertEqual(winner, .host)
        } else {
            XCTFail("Expected .matchOver(winner: .host), got \(state.matchPhase)")
        }
    }

    func test_peerSilenceTimeoutEndsMatchForLocalRole() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        state.setPeerSilenceTimeoutForTests(0.05)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 20_000_000)
        fake.simulateIncoming(.startMatch(winningScore: 5))
        try? await Task.sleep(nanoseconds: 20_000_000)
        let snap = makeSnapshot(balls: [BallState(x: 0.5, y: 0.5, vx: 0, vy: 0.5)])
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 20_000_000)
        // Now wait well past the 50ms injected timeout — peer is "silent".
        try? await Task.sleep(nanoseconds: 120_000_000)
        state.tick(dt: 1.0 / 60.0)
        if case .matchOver(let winner) = state.matchPhase {
            XCTAssertEqual(winner, .client)
        } else {
            XCTFail("Expected .matchOver(winner: .client), got \(state.matchPhase)")
        }
    }

    func test_recentPeerActivityDoesNotTriggerSilenceTimeout() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        state.setPeerSilenceTimeoutForTests(0.5)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 20_000_000)
        fake.simulateIncoming(.startMatch(winningScore: 5))
        try? await Task.sleep(nanoseconds: 20_000_000)
        let snap = makeSnapshot(
            balls: [BallState(x: 0.5, y: 0.5, vx: 0, vy: 0.5)],
            hostScore: 1, clientScore: 0
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.tick(dt: 1.0 / 60.0)
        // Still well inside the 500ms window — match must continue.
        XCTAssertEqual(state.matchPhase, .playing)
    }

    func test_hostReceivingClientReadyTransitionsToConfiguringMatch() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .waitingForOpponentAccept)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
    }

    func test_hostStartMatchSendsAndPlaysWithStoredWinningScore() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { state.startMatch(winningScore: 3) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(state.matchPhase, .playing)
        XCTAssertEqual(state.winningScore, 3)
        let starts: [Int?] = fake.sentMessages.compactMap {
            if case .startMatch(let s) = $0.message { return s } else { return nil }
        }
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(starts[0], 3)
        XCTAssertEqual(state.game.phase, .playing)
    }

    func test_clientReceivingStartMatchTransitionsToPlayingWithWinningScore() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
        fake.simulateIncoming(.startMatch(winningScore: 7))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .playing)
        XCTAssertEqual(state.winningScore, 7)
    }

    func test_clientReceivingStartMatchWithNilWinningScoreEntersNoLimitMode() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.startMatch(winningScore: nil))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .playing)
        XCTAssertNil(state.winningScore)
    }

    func test_cancelMatchConfigurationFromConfiguringDisconnectsAndReturnsToPairing() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
        await MainActor.run { state.cancelMatchConfiguration() }
        XCTAssertEqual(state.matchPhase, .pairing)
        XCTAssertEqual(fake.connectionState, .idle)
    }

    func test_cancelMatchConfigurationFromWaitingForOpponentAcceptDisconnectsAndReturnsToPairing() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .waitingForOpponentAccept)
        await MainActor.run { state.cancelMatchConfiguration() }
        XCTAssertEqual(state.matchPhase, .pairing)
        XCTAssertEqual(fake.connectionState, .idle)
    }

    func test_disconnectDuringConfiguringMatchReturnsToPairingNotMatchOver() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
        fake.simulateDisconnect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .pairing)
    }

    func test_clientAppliesBallsPickupAndEffectsYFlipped() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let snap = makeSnapshot(
            balls: [BallState(x: 0.3, y: 0.2, vx: 0.1, vy: 0.5)],
            hostEffects: EffectsState(wideRemaining: 5, hasShield: true, stickyArmed: false),
            clientEffects: EffectsState(wideRemaining: 0, hasShield: false, stickyArmed: true),
            pickup: PickupState(kind: .shield, x: 0.5, y: 0.3, driftSign: 1)
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(state.game.balls[0].position.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(state.game.balls[0].velocity.dy, -0.5, accuracy: 0.0001)
        // Host effects render on the client's TOP side; client effects on BOTTOM.
        XCTAssertTrue(state.game.powerUps.hasShield(for: .top))
        XCTAssertTrue(state.game.powerUps.stickyArmed(for: .bottom))
        XCTAssertEqual(state.game.powerUps.pickup?.position.y ?? -1, 0.7, accuracy: 0.0001)
    }

    func test_hostBumpsClientScoreWhenBallExitsHostSide() async {
        let fake = FakeMultiplayerService()
        let game = GameState()
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.startMatch(winningScore: 5)
        game.countdownRemaining = nil
        game.ball = Ball(position: CGPoint(x: 0.9, y: 0.995), velocity: CGVector(dx: 0, dy: 0.5))
        state.tick(dt: 0.05)
        XCTAssertEqual(state.clientScore, 1)
        XCTAssertEqual(state.matchPhase, .playing)
    }

    func test_clientTapSendsStickyRelease() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.localTapRelease()
        let releases = fake.sentMessages.filter {
            if case .stickyRelease = $0.message { return true } else { return false }
        }
        XCTAssertEqual(releases.count, 1)
    }

    func test_hostHandlesStickyReleaseForClientSide() async {
        let fake = FakeMultiplayerService()
        let game = GameState()
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        game.phase = .playing
        game.topSideIsAI = false
        game.grantPowerUpForTests(.stickyBall, to: .top)
        let paddleBottomY = GameConstants.paddleMarginY + GameConstants.paddleHeight / 2
        game.ball = Ball(position: CGPoint(x: 0.5, y: paddleBottomY + GameConstants.ballRadius + 0.001),
                         velocity: CGVector(dx: 0, dy: -0.3))
        game.update(dt: 0.05)
        XCTAssertEqual(game.stuckBall?.side, .top)
        fake.simulateIncoming(.stickyRelease)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(game.stuckBall)
        XCTAssertGreaterThan(game.ball.velocity.dy, 0)
    }

    func test_clientFiresSuccessHapticOnOwnPickupCollected() async {
        let fake = FakeMultiplayerService()
        let haptics = FakeHapticPlayer()
        let game = GameState(hapticPlayer: haptics)
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.snapshot(makeSnapshot(pickupCollected: .client)))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(haptics.successCount, 1)
    }
}

// MARK: - Test helpers

final class RecordingHapticPlayer: HapticPlayer {
    var clickCount = 0
    var successCount = 0
    func playClick() { clickCount += 1 }
    func playSuccess() { successCount += 1 }
}

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
