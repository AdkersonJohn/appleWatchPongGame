import SwiftUI

/// Shown to the host once both peers are connected. The host picks a target
/// score; tapping a button starts the match for both watches.
struct MatchConfigView: View {
    let onPick: (Int?) -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 6) {
                Text("Play to")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Choose target score")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer().frame(height: 2)

                scoreButton(label: "First to 3") { onPick(3) }
                scoreButton(label: "First to 5") { onPick(5) }
                scoreButton(label: "No limit")   { onPick(nil) }

                Button("Back", action: onBack)
                    .foregroundColor(.white.opacity(0.7))
                    .font(.footnote)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func scoreButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MatchConfigView(onPick: { _ in }, onBack: {})
}
