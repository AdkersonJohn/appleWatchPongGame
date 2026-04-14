import XCTest
@testable import PongWatch_Watch_App

final class GameStateTests: XCTestCase {
    func test_resetPutsGameInStartPhaseAndCenteredBall() {
        let state = GameState()
        state.phase = .gameOver
        state.score = 42

        state.reset()

        XCTAssertEqual(state.phase, .start)
        XCTAssertEqual(state.score, 0)
        XCTAssertEqual(state.ball.position.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.ball.position.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.playerPaddleX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.aiPaddleX, 0.5, accuracy: 0.0001)
    }

    func test_startGameMovesToPlayingPhase() {
        let state = GameState()
        state.startGame()
        XCTAssertEqual(state.phase, .playing)
    }

    func test_startGameSetsBallVelocityWithExpectedMagnitude() {
        let state = GameState()
        state.startGame()
        let mag = hypot(state.ball.velocity.dx, state.ball.velocity.dy)
        XCTAssertEqual(mag, GameConstants.initialBallSpeed, accuracy: 0.0001)
    }

    func test_updateMovesBallByVelocityTimesDt() {
        let state = GameState()
        state.phase = .playing
        state.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                          velocity: CGVector(dx: 0.2, dy: -0.1))

        state.update(dt: 0.5)

        XCTAssertEqual(state.ball.position.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(state.ball.position.y, 0.45, accuracy: 0.0001)
    }

    func test_updateDoesNothingWhenNotPlaying() {
        let state = GameState()
        state.phase = .start
        state.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                          velocity: CGVector(dx: 0.2, dy: 0.0))

        state.update(dt: 0.5)

        XCTAssertEqual(state.ball.position.x, 0.5, accuracy: 0.0001)
    }

    func test_ballBouncesOffLeftWall() {
        let state = GameState()
        state.phase = .playing
        // Ball near left wall moving further left
        state.ball = Ball(position: CGPoint(x: GameConstants.ballRadius * 0.5, y: 0.5),
                          velocity: CGVector(dx: -0.5, dy: 0))

        state.update(dt: 0.01)

        XCTAssertGreaterThan(state.ball.velocity.dx, 0, "Velocity.dx should flip to positive")
        XCTAssertGreaterThanOrEqual(state.ball.position.x, GameConstants.ballRadius)
    }

    func test_ballBouncesOffRightWall() {
        let state = GameState()
        state.phase = .playing
        state.ball = Ball(position: CGPoint(x: 1.0 - GameConstants.ballRadius * 0.5, y: 0.5),
                          velocity: CGVector(dx: 0.5, dy: 0))

        state.update(dt: 0.01)

        XCTAssertLessThan(state.ball.velocity.dx, 0, "Velocity.dx should flip to negative")
        XCTAssertLessThanOrEqual(state.ball.position.x, 1.0 - GameConstants.ballRadius)
    }

    func test_ballHitsPlayerPaddleAndBouncesUp() {
        let state = GameState()
        state.phase = .playing
        state.playerPaddleX = 0.5
        let paddleY = 1.0 - GameConstants.paddleMarginY
        // Ball just above paddle, moving down into it
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: paddleY - GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.05)

        XCTAssertLessThan(state.ball.velocity.dy, 0, "Should bounce upward")
        XCTAssertEqual(state.score, 1)
    }

    func test_ballMissesPlayerPaddleWhenOffsetHorizontally() {
        let state = GameState()
        state.phase = .playing
        state.playerPaddleX = 0.2  // Paddle on left
        let paddleY = 1.0 - GameConstants.paddleMarginY
        // Ball at x=0.8, clearly not above paddle
        state.ball = Ball(
            position: CGPoint(x: 0.8, y: paddleY - GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.05)

        XCTAssertGreaterThan(state.ball.velocity.dy, 0, "Ball should keep moving down")
        XCTAssertEqual(state.score, 0)
    }

    func test_ballHitEdgeOfPaddleDeflectsAtAngle() {
        let state = GameState()
        state.phase = .playing
        state.playerPaddleX = 0.5
        let paddleY = 1.0 - GameConstants.paddleMarginY
        // Hit the right edge of the paddle
        let hitX = 0.5 + GameConstants.paddleWidth / 2 - 0.005
        state.ball = Ball(
            position: CGPoint(x: hitX, y: paddleY - GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.05)

        XCTAssertLessThan(state.ball.velocity.dy, 0, "Bounces up")
        XCTAssertGreaterThan(state.ball.velocity.dx, 0, "Deflects to the right")
    }

    func test_ballHitsAIPaddleAndBouncesDown() {
        let state = GameState()
        state.phase = .playing
        state.aiPaddleX = 0.5
        let paddleY = GameConstants.paddleMarginY
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: paddleY + GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: -0.5)
        )

        state.update(dt: 0.05)

        XCTAssertGreaterThan(state.ball.velocity.dy, 0, "Should bounce down")
        XCTAssertEqual(state.score, 0, "AI hit does not change score")
    }
}
