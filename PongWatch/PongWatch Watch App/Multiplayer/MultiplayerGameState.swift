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
        // Filled in by later tasks.
    }

    // MARK: - Host tick

    /// Called once per render tick on the host. Advances physics and sends a snapshot.
    /// No-op on the client.
    func tickIfHost(dt: CGFloat) {
        guard service.role == .host else { return }
        game.update(dt: dt)
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
