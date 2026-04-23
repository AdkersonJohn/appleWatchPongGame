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
}
