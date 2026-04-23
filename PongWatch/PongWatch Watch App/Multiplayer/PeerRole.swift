import Foundation

enum PeerRole: String, Codable, Equatable {
    case host
    case client

    /// Role from the *other* side's perspective (used when flipping snapshot fields).
    var opposite: PeerRole {
        self == .host ? .client : .host
    }
}
