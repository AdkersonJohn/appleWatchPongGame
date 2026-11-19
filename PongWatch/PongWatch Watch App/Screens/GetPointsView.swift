import SwiftUI
import StoreKit

/// Whether the packs may be sold right now.
enum GetPointsAvailability {
    case sellable
    case nothingLeftToBuy

    /// Selling currency that buys nothing is an anti-goal (and App Review 3.1.1):
    /// stop once the balance already covers everything the player doesn't own.
    static func current(store: ProgressionStore) -> GetPointsAvailability {
        let leftToBuy = UnlockCatalog.all.filter { !store.isUnlocked($0) }.map(\.cost).reduce(0, +)
        return store.availablePoints >= leftToBuy ? .nothingLeftToBuy : .sellable
    }
}

/// Buy points: four fixed packs and a custom amount in tens.
struct GetPointsView: View {
    let chasing: Unlockable?
    let onDone: () -> Void

    @EnvironmentObject private var purchases: PurchaseService
    @State private var store = ProgressionStore()
    @State private var quantity = 1
    @State private var message: String?
    @State private var loaded = false

    private var availability: GetPointsAvailability { GetPointsAvailability.current(store: store) }
    private var canBuy: Bool { availability == .sellable && !purchases.isPurchasing }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 8) {
                    Text("\(store.availablePoints) pts")
                        .font(.title3).bold()
                        .foregroundColor(.yellow)
                    if let item = chasing {
                        let short = max(0, item.cost - store.availablePoints)
                        Text(short > 0 ? "\(item.name) costs \(item.cost) pts, \(short) more to go"
                                       : "You can now afford \(item.name)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    if availability == .nothingLeftToBuy {
                        Text("You already have enough points for everything left.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    if purchases.packs.isEmpty {
                        unavailable
                    } else {
                        ForEach(purchases.packs, id: \.pack.id) { entry in
                            packRow(entry.pack, entry.product)
                        }
                        custom
                    }

                    if let message {
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    Button("Back", action: onDone)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 8)
            }
        }
        .task {
            await purchases.load()
            loaded = true
        }
        // A launch-time credit can land while this screen is open.
        .onChange(of: purchases.walletChanges) { _ in refresh() }
    }

    /// The store is plain UserDefaults, so re-read it after the wallet moves.
    private func refresh() { store = ProgressionStore() }

    @ViewBuilder
    private var unavailable: some View {
        if loaded {
            Text("The App Store isn't available right now.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Try again") {
                loaded = false
                Task { await purchases.load(); loaded = true }
            }
            .font(.footnote)
        } else {
            ProgressView()
        }
    }

    private func packRow(_ pack: PointPack, _ product: Product) -> some View {
        Button {
            buy(pack, quantity: 1)
        } label: {
            HStack {
                Text("+\(pack.points) pts")
                    .font(.body).bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(product.displayPrice)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.yellow)
                    .cornerRadius(4)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.white.opacity(0.14))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!canBuy)
        .opacity(canBuy ? 1 : 0.4)
    }

    @ViewBuilder
    private var custom: some View {
        if let product = purchases.packs.first(where: { $0.pack == PointPack.custom })?.product {
            let points = quantity * PointPack.custom.points
            VStack(spacing: 6) {
                Text("Custom")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                HStack(spacing: 8) {
                    stepButton("minus", enabled: quantity > 1) { quantity -= 1 }
                    Text("\(points)")
                        .font(.title3).bold()
                        .frame(minWidth: 48)
                    stepButton("plus", enabled: quantity < PurchaseService.maxQuantity) { quantity += 1 }
                }
                Button {
                    buy(PointPack.custom, quantity: quantity)
                } label: {
                    Text("Buy \(points) pts for \(product.priceFormatStyle.format(product.price * Decimal(quantity)))")
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.yellow)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canBuy)
                .opacity(canBuy ? 1 : 0.4)
            }
            .padding(8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.18))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private func buy(_ pack: PointPack, quantity: Int) {
        message = nil
        Task {
            do {
                switch try await purchases.purchase(pack, quantity: quantity) {
                case .credited(let points): message = "Added \(points) pts"
                case .pending: message = "Waiting for approval. Points arrive when it clears."
                // Nothing to say: a cancel is the player's own choice, and a
                // purchase the launch listener already credited isn't a failure.
                case .cancelled, .alreadyCredited: break
                }
            } catch {
                message = "That purchase didn't go through."
            }
            refresh()
        }
    }
}
