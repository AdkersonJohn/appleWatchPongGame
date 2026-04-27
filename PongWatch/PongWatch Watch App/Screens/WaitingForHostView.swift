import SwiftUI

/// Shown to the client during the configuration phase while the host picks
/// the target score on MatchConfigView.
struct WaitingForHostView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Waiting for host")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("They're choosing the target score…")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    WaitingForHostView()
}
