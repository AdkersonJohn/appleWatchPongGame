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

    func update(dt: CGFloat) {
        guard phase == .playing else { return }

        ball.position.x += ball.velocity.dx * dt
        ball.position.y += ball.velocity.dy * dt

        // Left wall
        if ball.position.x < GameConstants.ballRadius {
            ball.position.x = GameConstants.ballRadius
            ball.velocity.dx = -ball.velocity.dx
        }
        // Right wall
        if ball.position.x > 1.0 - GameConstants.ballRadius {
            ball.position.x = 1.0 - GameConstants.ballRadius
            ball.velocity.dx = -ball.velocity.dx
        }

        // Player paddle (bottom)
        let playerPaddleY = 1.0 - GameConstants.paddleMarginY
        let playerPaddleTop = playerPaddleY - GameConstants.paddleHeight / 2
        if ball.velocity.dy > 0,
           ball.position.y + GameConstants.ballRadius >= playerPaddleTop,
           ball.position.y + GameConstants.ballRadius <= playerPaddleY + GameConstants.paddleHeight / 2,
           abs(ball.position.x - playerPaddleX) <= GameConstants.paddleWidth / 2 {
            bouncePaddleHit(paddleX: playerPaddleX)
            score += 1
        }

        // AI paddle (top)
        let aiPaddleY = GameConstants.paddleMarginY
        let aiPaddleBottom = aiPaddleY + GameConstants.paddleHeight / 2
        if ball.velocity.dy < 0,
           ball.position.y - GameConstants.ballRadius <= aiPaddleBottom,
           ball.position.y - GameConstants.ballRadius >= aiPaddleY - GameConstants.paddleHeight / 2,
           abs(ball.position.x - aiPaddleX) <= GameConstants.paddleWidth / 2 {
            bouncePaddleHit(paddleX: aiPaddleX)
        }

        // Ball exits top (AI missed) — reset ball, keep playing
        if ball.position.y < 0 {
            ball.position = CGPoint(x: 0.5, y: 0.5)
            ball.velocity = randomInitialVelocity(speed: currentBallSpeed)
        }

        // Ball exits bottom — game over
        if ball.position.y > 1.0 {
            phase = .gameOver
        }
    }

    private func bouncePaddleHit(paddleX: CGFloat) {
        ball.velocity.dy = -ball.velocity.dy
        // Impact offset: -1 (left edge) to +1 (right edge)
        let offset = (ball.position.x - paddleX) / (GameConstants.paddleWidth / 2)
        let clamped = max(-1, min(1, offset))
        let speed = hypot(ball.velocity.dx, ball.velocity.dy)
        // Steer dx toward offset while preserving overall speed
        let steerAmount: CGFloat = 0.7
        let newDx = clamped * speed * steerAmount
        // Recompute dy to preserve speed magnitude
        let newDySquared = max(0, speed * speed - newDx * newDx)
        let newDy = (ball.velocity.dy < 0 ? -1 : 1) * sqrt(newDySquared)
        ball.velocity.dx = newDx
        ball.velocity.dy = newDy
    }

    private func randomInitialVelocity(speed: CGFloat) -> CGVector {
        // Angle between 30° and 60° off vertical, random quadrant
        let angle = CGFloat.random(in: (.pi / 6)...(.pi / 3))
        let dx = sin(angle) * speed * (Bool.random() ? 1 : -1)
        let dy = cos(angle) * speed * (Bool.random() ? 1 : -1)
        return CGVector(dx: dx, dy: dy)
    }
}
