import SwiftUI

/// Shown to the host after they invite a peer but before the peer has tapped
/// Accept. Once `.clientReady` arrives the host transitions to MatchConfigView.
struct WaitingForAcceptView: View {
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Waiting for opponent")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Invite sent — they need to accept on their watch")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.7))
                    .padding(.top, 4)
                Spacer().frame(height: 4)
                Button("Cancel", action: onCancel)
                    .foregroundColor(.white.opacity(0.7))
                    .font(.footnote)
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    WaitingForAcceptView(onCancel: {})
}
