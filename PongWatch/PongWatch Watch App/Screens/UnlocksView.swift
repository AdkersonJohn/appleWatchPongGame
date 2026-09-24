import SwiftUI

/// Spend points on celebrations, skins, titles and abilities.
///
/// One flat list grouped by category: on a 40mm screen a tab bar or grid costs
/// more taps than it saves, and every row has to say price and state on its own
/// because there is no room for a legend.
struct UnlocksView: View {
    let onBack: () -> Void
    @State private var store = ProgressionStore()
    /// Bumped on every purchase so the list redraws; the store is plain
    /// UserDefaults rather than an observable object.
    @State private var revision = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    Text("\(store.availablePoints) pts")
                        .font(.title3).bold()
                        .foregroundColor(.yellow)
                    Text("Earned \(store.lifetimePoints) all-time")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))

                    ForEach(UnlockCategory.allCases, id: \.self) { category in
                        VStack(spacing: 4) {
                            Text(category.label)
                                .font(.caption).bold()
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if category == .ability {
                                Text("Single player only")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(UnlockCatalog.all.filter { $0.category == category }) { item in
                                row(for: item)
                            }
                        }
                    }

                    Button("Back", action: onBack)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 8)
            }
        }
        .id(revision)
    }

    @ViewBuilder
    private func row(for item: Unlockable) -> some View {
        let owned = store.isUnlocked(item)
        let equipped = store.equipped(in: item.category) == item.id
            || (store.equipped(in: item.category) == nil && item.cost == 0)
        let affordable = store.availablePoints >= item.cost

        Button {
            if owned { store.equip(item) } else if store.buy(item) { store.equip(item) }
            revision += 1
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.body)
                        .foregroundColor(owned ? .white : .white.opacity(affordable ? 0.9 : 0.45))
                    Text(owned ? item.detail : "\(item.cost) pts")
                        .font(.caption2)
                        .foregroundColor(owned ? .white.opacity(0.5) : .yellow.opacity(affordable ? 0.9 : 0.4))
                }
                Spacer()
                if equipped {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else if !owned && !affordable {
                    Image(systemName: "lock.fill").foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(equipped ? Color.green.opacity(0.18) : Color.white.opacity(0.12))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!owned && !affordable)
    }
}

#Preview {
    UnlocksView(onBack: {})
}
