import Foundation
import CoreGraphics
import Combine
import Network

enum MultiplayerMatchPhase: Equatable {
    case pairing
    case playing
    case pausedByOpponent
    case matchOver(winner: PeerRole)
    case disconnected
}

final class MultiplayerGameState: ObservableObject {
    // Public, observable state
    @Published private(set) var matchPhase: MultiplayerMatchPhase = .pairing
    @Published private(set) var role: PeerRole? = nil
    @Published private(set) var hostScore: Int = 0
    @Published private(set) var clientScore: Int = 0
    /// Inner game state used for local rendering on both roles.
    @Published private(set) var game: GameState

    private let service: any MultiplayerServiceProtocol
    private var cancellables: Set<AnyCancellable> = []
    private var incomingTask: Task<Void, Never>?
    private var tickSeq: UInt32 = 0
    private var lastReceivedTickSeq: UInt32 = 0
    private var lastPaddleInputSeq: UInt32 = 0
    private var localPaddleInputSeq: UInt32 = 0

    init(service: any MultiplayerServiceProtocol,
         game: GameState = GameState()) {
        self.service = service
        self.game = game
        observeService()
        startConsumingMessages()
    }

    deinit { incomingTask?.cancel() }

    private func observeService() {
        // Bridge state changes on the service into our own state flow.
        // `statePublisher` is a type-erased AnyPublisher<Void, Never> that fires
        // whenever any @Published property on the service changes.
        service.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // statePublisher fires *before* the new value is visible (objectWillChange);
                // defer one hop so the new values are readable.
                DispatchQueue.main.async { self?.handleServiceStateChange() }
            }
            .store(in: &cancellables)
    }

    private func handleServiceStateChange() {
        let priorRole = self.role
        let newRole = service.role
        switch service.connectionState {
        case .connected:
            self.role = newRole
            if matchPhase == .pairing {
                matchPhase = .playing
            }
        case .disconnected:
            let winnerRole = priorRole ?? newRole
            self.role = nil
            // If a previous handler already resolved the match (e.g. to
            // .matchOver on a mid-match drop), don't clobber it.
            if case .matchOver = matchPhase { return }
            if matchPhase == .playing || matchPhase == .pausedByOpponent {
                if let winner = winnerRole {
                    matchPhase = .matchOver(winner: winner)
                } else {
                    matchPhase = .disconnected
                }
            } else {
                matchPhase = .disconnected
            }
        default:
            self.role = newRole
        }
    }

    private func startConsumingMessages() {
        let stream = service.incomingMessages
        incomingTask = Task { [weak self] in
            for await msg in stream {
                await self?.handle(msg)
            }
        }
    }

    @MainActor
    private func handle(_ message: NetworkMessage) {
        switch message {
        case .snapshot(let snap):
            applyIncomingSnapshot(snap)
        case .paddleInput(let input):
            applyIncomingPaddleInput(input)
        case .rematchRequest:
            handleRematchRequest()
        case .endMatch:
            matchPhase = .disconnected
        case .paused(_):
            if matchPhase == .playing { matchPhase = .pausedByOpponent }
        case .resumed(_):
            if matchPhase == .pausedByOpponent { matchPhase = .playing }
        case .forfeit(let by):
            let winner: PeerRole = (by == .host) ? .client : .host
            matchPhase = .matchOver(winner: winner)
        }
    }

    // MARK: - Client snapshot apply

    private func applyIncomingSnapshot(_ snap: GameSnapshot) {
        guard service.role == .client else { return }
        let delta = snap.tickSeq &- lastReceivedTickSeq
        if delta == 0 || delta > UInt32.max / 2 { return }
        lastReceivedTickSeq = snap.tickSeq

        game.ball = Ball(
            position: CGPoint(x: snap.ballX, y: 1.0 - snap.ballY),
            velocity: CGVector(dx: snap.ballVX, dy: -snap.ballVY)
        )
        // DO NOT overwrite game.playerPaddleX — that's our locally predicted paddle.
        game.aiPaddleX = snap.hostPaddleX
        game.score = snap.clientScore
        game.countdownRemaining = snap.countdownRemaining
        game.phase = snap.phase

        hostScore = snap.hostScore
        clientScore = snap.clientScore

        if snap.clientPaddleHit {
            game.playPaddleHitHaptic()
        }

        // Celebrate only if we scored.
        if let event = snap.scoreEvent, event.scoredBy == .client {
            game.spawnScoreBurst(atX: event.impactX)
        }
    }

    // MARK: - Placeholder handlers (implemented in later tasks)

    private func applyIncomingPaddleInput(_ input: PaddleInput) {
        guard service.role == .host else { return }
        let delta = input.tickSeq &- lastPaddleInputSeq
        if delta == 0 || delta > UInt32.max / 2 { return }
        lastPaddleInputSeq = input.tickSeq
        game.aiPaddleX = input.paddleX
    }

    // MARK: - Post-match

    func requestRematch() {
        guard service.role != nil else { return }
        service.send(.rematchRequest, reliable: true)
        startFreshMatch()
    }

    private func startFreshMatch() {
        hostScore = 0
        clientScore = 0
        tickSeq = 0
        lastReceivedTickSeq = 0
        lastPaddleInputSeq = 0
        localPaddleInputSeq = 0
        game.prepareNextServe()
        game.phase = .playing
        matchPhase = .playing
    }

    func leaveMatch() {
        service.disconnect()
        matchPhase = .pairing
    }

    private func handleRematchRequest() {
        startFreshMatch()
    }

    // MARK: - Paddle input

    /// View calls this when the Digital Crown changes. Works for both roles.
    func setLocalPaddle(normalizedCrown value: CGFloat) {
        let clamped = max(0, min(1, value))
        // Both roles update their own inner-game player paddle for local rendering.
        game.setPlayerPaddle(normalizedCrown: clamped)
        if service.role == .client {
            localPaddleInputSeq &+= 1
            let input = PaddleInput(
                protoVersion: GameConstants.multiplayerProtocolVersion,
                paddleX: clamped,
                tickSeq: localPaddleInputSeq
            )
            service.send(.paddleInput(input), reliable: false)
        }
    }

    // MARK: - Host tick

    /// Called once per render tick on the host. Advances physics and sends a snapshot.
    /// No-op on the client.
    func tickIfHost(dt: CGFloat) {
        guard service.role == .host else { return }
        let scoreBefore = game.score
        let phaseBefore = game.phase
        let clientPaddleBeforeTick = game.aiPaddleX
        let ballVYBefore = game.ball.velocity.dy

        game.update(dt: dt)
        game.aiPaddleX = clientPaddleBeforeTick

        // Client paddle hit: ball was moving up (negative dy in host space) and is
        // now moving down (positive dy) with the ball near the top paddle line.
        let clientPaddleHit = ballVYBefore < 0 && game.ball.velocity.dy > 0 &&
                              game.ball.position.y < GameConstants.paddleMarginY + GameConstants.paddleHeight

        // Host paddle hit: ball was moving down and is now moving up near the bottom.
        let hostPaddleHit = ballVYBefore > 0 && game.ball.velocity.dy < 0 &&
                            game.ball.position.y > 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight

        var pendingScoreEvent: ScoreEvent? = nil

        // Host scored: inner game's score went up (ball exited top in host space).
        if game.score > scoreBefore {
            hostScore += game.score - scoreBefore
            pendingScoreEvent = ScoreEvent(impactX: game.ball.position.x, scoredBy: .host)
        }

        // Client scored: inner game flipped to .gameOver because ball exited bottom.
        if phaseBefore == .playing && game.phase == .gameOver {
            clientScore += 1
            pendingScoreEvent = ScoreEvent(impactX: game.ball.position.x, scoredBy: .client)
            game.phase = .playing
            game.prepareNextServe()
        }

        // Check match-over.
        if hostScore >= GameConstants.multiplayerWinningScore {
            finishMatch(winner: .host)
        } else if clientScore >= GameConstants.multiplayerWinningScore {
            finishMatch(winner: .client)
        }

        broadcastSnapshot(
            scoreEvent: pendingScoreEvent,
            hostPaddleHit: hostPaddleHit,
            clientPaddleHit: clientPaddleHit
        )

        // Only the host spawns particles on its own score. The client will spawn
        // from the snapshot event in applyIncomingSnapshot.
        if let ev = pendingScoreEvent, ev.scoredBy == .host {
            game.spawnScoreBurst(atX: ev.impactX)
        }
    }

    private func finishMatch(winner: PeerRole) {
        matchPhase = .matchOver(winner: winner)
    }

    // MARK: - Scene-phase / wrist-down handling

    enum LocalScenePhase { case active, inactive }

    private var graceSeconds: Double = GameConstants.multiplayerGraceSeconds
    private var wristDownTask: Task<Void, Never>?

    func setGraceSecondsForTests(_ seconds: Double) {
        graceSeconds = seconds
    }

    func onScenePhaseChanged(to phase: LocalScenePhase) {
        guard case .playing = matchPhase else { return }
        switch phase {
        case .inactive:
            guard let role = service.role else { return }
            service.send(.paused(role: role), reliable: true)
            wristDownTask?.cancel()
            let grace = graceSeconds
            wristDownTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    self.service.send(.forfeit(by: role), reliable: true)
                    self.matchPhase = .matchOver(winner: role.opposite)
                }
            }
        case .active:
            wristDownTask?.cancel()
            wristDownTask = nil
            guard let role = service.role else { return }
            service.send(.resumed(role: role), reliable: true)
        }
    }

    private func broadcastSnapshot(
        scoreEvent: ScoreEvent? = nil,
        hostPaddleHit: Bool = false,
        clientPaddleHit: Bool = false
    ) {
        tickSeq &+= 1
        let snap = GameSnapshot(
            protoVersion: GameConstants.multiplayerProtocolVersion,
            phase: game.phase,
            ballX: game.ball.position.x,
            ballY: game.ball.position.y,
            ballVX: game.ball.velocity.dx,
            ballVY: game.ball.velocity.dy,
            hostPaddleX: game.playerPaddleX,
            clientPaddleX: game.aiPaddleX,
            hostScore: hostScore,
            clientScore: clientScore,
            countdownRemaining: game.countdownRemaining,
            scoreEvent: scoreEvent,
            hostPaddleHit: hostPaddleHit,
            clientPaddleHit: clientPaddleHit,
            tickSeq: tickSeq
        )
        service.send(.snapshot(snap), reliable: false)
    }
}
