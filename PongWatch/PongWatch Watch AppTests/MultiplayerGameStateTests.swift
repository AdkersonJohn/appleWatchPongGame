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
}
