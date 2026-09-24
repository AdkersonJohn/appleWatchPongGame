import XCTest
import Network
@testable import PongWatch_Watch_App

final class PairingScreenTests: XCTestCase {
    private var peer: DiscoveredPeer {
        DiscoveredPeer(id: "p", displayName: "John's iPhone",
                       endpoint: .service(name: "p", type: "_pongwatch._tcp", domain: "local.", interface: nil),
                       platform: "phone")
    }

    /// The reported bug: tapping a peer left the lobby on screen, so an invite
    /// that was still connecting — or never would — looked like a dead button.
    func test_invitingShowsTheWaitingScreenNotTheLobby() {
        XCTAssertEqual(PairingScreen.screen(for: .inviting(peer)), .waitingForAccept)
    }

    func test_incomingInviteStillShowsThePrompt() {
        XCTAssertEqual(PairingScreen.screen(for: .receivingInvite(fromDisplayName: "Watch")),
                       .invitePrompt("Watch"))
    }

    func test_idleAndDiscoveringShowTheLobby() {
        XCTAssertEqual(PairingScreen.screen(for: .idle), .lobby)
        XCTAssertEqual(PairingScreen.screen(for: .discovering), .lobby)
    }

    /// A failed invite has to release the player back to the list, or they are
    /// stuck on a spinner with no way to retry.
    func test_failureReturnsToTheLobby() {
        XCTAssertEqual(PairingScreen.screen(for: .failed("boom")), .lobby)
    }
}

final class FieldShapeTests: XCTestCase {
    private let tallPhone: CGFloat = 440.0 / 956.0

    /// A watch cannot letterbox a tall phone field into anything playable, so
    /// any match involving a watch is played on the watch's shape.
    func test_watchAgainstPhoneUsesTheWatchShape() {
        XCTAssertEqual(FieldShape.agreed(hostIsWatch: false, clientIsWatch: true, hostAspect: tallPhone),
                       GameConstants.watchPlayfieldAspect)
        XCTAssertEqual(FieldShape.agreed(hostIsWatch: true, clientIsWatch: false, hostAspect: tallPhone),
                       GameConstants.watchPlayfieldAspect)
    }

    func test_phoneAgainstPhoneKeepsTheTallField() {
        XCTAssertEqual(FieldShape.agreed(hostIsWatch: false, clientIsWatch: false, hostAspect: tallPhone),
                       tallPhone)
    }

    /// Both devices must scale their physics identically or the ball lands in
    /// different places on the two screens.
    func test_agreedShapeConvertsToTheSameVerticalScaleOnBothSides() {
        let scale = FieldShape.verticalScale(forAspect: GameConstants.watchPlayfieldAspect)
        XCTAssertEqual(scale, 1, accuracy: 0.0001, "the watch's own shape must leave physics untouched")
    }
}
