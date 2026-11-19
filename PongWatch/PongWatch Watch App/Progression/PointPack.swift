import Foundation

/// A purchasable bundle of points. Carries only the point value: prices live in
/// App Store Connect and reach the UI through `Product.displayPrice`.
struct PointPack: Identifiable, Equatable {
    /// The App Store product id.
    let id: String
    let points: Int

    static let all: [PointPack] = [
        PointPack(id: "com.johnadkerson.PongWatch.points10", points: 10),
        PointPack(id: "com.johnadkerson.PongWatch.points50", points: 50),
        PointPack(id: "com.johnadkerson.PongWatch.points100", points: 100),
        PointPack(id: "com.johnadkerson.PongWatch.points500", points: 500),
    ]

    /// A custom amount is the smallest pack bought with a quantity.
    static let custom = all[0]

    /// Points a transaction is worth, or nil when it isn't one of our packs.
    /// Revocation is the caller's call: it needs the points to reverse them.
    /// Quantity is what StoreKit says was bought, not what we asked for.
    static func pointsToCredit(productID: String, quantity: Int) -> Int? {
        guard quantity > 0,
              let pack = all.first(where: { $0.id == productID }) else { return nil }
        return pack.points * quantity
    }
}
