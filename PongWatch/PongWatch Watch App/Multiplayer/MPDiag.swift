import Foundation
import Combine
import os

/// Diagnostics for the peer-to-peer lobby.
///
/// Two sinks on purpose. `os_log` is the good one, but it needs a Mac running
/// Console attached to the watch — which a remote tester does not have. So
/// every event also lands in an in-memory ring buffer the lobby can draw
/// on-screen, which is the only channel that reaches someone debugging from
/// their wrist in another building.
@MainActor
final class MPDiag: ObservableObject {
    static let shared = MPDiag()

    private let log = Logger(subsystem: "com.johnadkerson.PongWatch", category: "multiplayer")
    /// Newest last. Capped so a long lobby session can't grow unbounded.
    @Published private(set) var lines: [String] = []
    private var origin = Date()

    private static let capacity = 60

    func event(_ text: String) {
        log.info("\(text, privacy: .public)")
        let stamp = String(format: "%5.1f", Date().timeIntervalSince(origin))
        lines.append("\(stamp) \(text)")
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }

    /// Called when the lobby opens so each attempt reads as a fresh timeline.
    func reset() {
        lines.removeAll()
        origin = Date()
    }
}
