import Foundation
import CoreGraphics
import Combine

final class GameState: ObservableObject {
    @Published var phase: GamePhase = .start
    @Published var ball: Ball
    @Published var playerPaddleX: CGFloat
    @Published var aiPaddleX: CGFloat
    @Published var score: Int = 0

    private var currentBallSpeed: CGFloat = GameConstants.initialBallSpeed

    init() {
        self.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                         velocity: .zero)
        self.playerPaddleX = 0.5
        self.aiPaddleX = 0.5
    }

    func reset() {
        phase = .start
        score = 0
        currentBallSpeed = GameConstants.initialBallSpeed
        ball = Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)
        playerPaddleX = 0.5
        aiPaddleX = 0.5
    }

    func startGame() {
        reset()
        phase = .playing
        ball.velocity = randomInitialVelocity(speed: currentBallSpeed)
    }

    private func randomInitialVelocity(speed: CGFloat) -> CGVector {
        // Angle between 30° and 60° off vertical, random quadrant
        let angle = CGFloat.random(in: (.pi / 6)...(.pi / 3))
        let dx = sin(angle) * speed * (Bool.random() ? 1 : -1)
        let dy = cos(angle) * speed * (Bool.random() ? 1 : -1)
        return CGVector(dx: dx, dy: dy)
    }
}
