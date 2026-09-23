import SwiftUI

struct MultiplayerGameOverView: View {
    let didWin: Bool
    let myScore: Int
    let opponentScore: Int
    /// When false, the Rematch button is hidden — used after the peer
    /// disconnects, since you can't rematch a peer who isn't there.
    let allowRematch: Bool
    let onRematch: () -> Void
    let onBack: () -> Void
    @ObservedObject private var diag = MPDiag.shared
    @State private var showDiagnostics = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(didWin ? "You Won!" : "You Lost")
                    .font(.title3)
                    .bold()
                    .foregroundColor(didWin ? .green : .red)
                Text("\(myScore) — \(opponentScore)")
                    .font(.title2)
                    .foregroundColor(.white)
                Spacer().frame(height: 4)
                if allowRematch {
                    Button(action: onRematch) {
                        Text("Rematch")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onBack) {
                    Text("Main Menu")
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button("Diagnostics") { showDiagnostics = true }
                    .font(.footnote)
                    .foregroundColor(.blue.opacity(0.8))
            }
            .padding(.horizontal, 12)
        }
        .sheet(isPresented: $showDiagnostics) {
            MPDiagnosticsView(lines: diag.lines)
                .onAppear { MPDiag.shared.flushTallies() }
        }
    }
}

#Preview("Win — rematch allowed") {
    MultiplayerGameOverView(didWin: true, myScore: 5, opponentScore: 3, allowRematch: true, onRematch: {}, onBack: {})
}

#Preview("Win — peer dropped, no rematch") {
    MultiplayerGameOverView(didWin: true, myScore: 3, opponentScore: 1, allowRematch: false, onRematch: {}, onBack: {})
}
