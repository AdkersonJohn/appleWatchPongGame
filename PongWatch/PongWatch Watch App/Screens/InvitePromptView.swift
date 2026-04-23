import SwiftUI

struct InvitePromptView: View {
    let peerName: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(peerName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("wants to play")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer().frame(height: 4)
                Button(action: onAccept) {
                    Text("Accept")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.35))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("Decline")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.35))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    InvitePromptView(peerName: "John's Apple Watch", onAccept: {}, onDecline: {})
}
