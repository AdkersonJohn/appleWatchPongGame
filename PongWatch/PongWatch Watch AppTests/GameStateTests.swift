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
}
