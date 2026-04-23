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
        self.role = service.role
        switch service.connectionState {
        case .connected:
            if matchPhase == .pairing {
                matchPhase = .playing
            }
        case .disconnected:
            matchPhase = .disconnected
        default:
            break
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
        // Drop out-of-order snapshots (wrap-safe compare).
        let delta = snap.tickSeq &- lastReceivedTickSeq
        if delta == 0 || delta > UInt32.max / 2 { return }
        lastReceivedTickSeq = snap.tickSeq

        // Flip host coords → client coords.
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
    }

    // MARK: - Placeholder handlers (implemented in later tasks)

    private func applyIncomingPaddleInput(_ input: PaddleInput) {
        guard service.role == .host else { return }
        let delta = input.tickSeq &- lastPaddleInputSeq
        if delta == 0 || delta > UInt32.max / 2 { return }
        lastPaddleInputSeq = input.tickSeq
        game.aiPaddleX = input.paddleX
    }

    private func handleRematchRequest() {
        // Task 15
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
        // Client paddle position is already stored in game.aiPaddleX by
        // applyIncomingPaddleInput. game.update(dt:) runs AI tracking over it,
        // so we revert to the client's actual position immediately after physics.
        let clientPaddleBeforeTick = game.aiPaddleX
        game.update(dt: dt)
        game.aiPaddleX = clientPaddleBeforeTick
        broadcastSnapshot()
    }

    private func broadcastSnapshot() {
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
            scoreEvent: nil,
            hostPaddleHit: false,
            clientPaddleHit: false,
            tickSeq: tickSeq
        )
        service.send(.snapshot(snap), reliable: false)
    }
}
