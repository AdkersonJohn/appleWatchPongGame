import SwiftUI

struct NearbyPlayersView<Service: MultiplayerServiceProtocol>: View {
    @ObservedObject var service: Service
    let onBack: () -> Void
    @ObservedObject private var diag = MPDiag.shared
    @State private var showDiagnostics = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Nearby Players")
                    .font(.headline)
                    .foregroundColor(.white)
                if service.discoveredPeers.isEmpty {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Searching…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Text("Make sure the other player is also on Multiplayer.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(service.discoveredPeers, id: \.self) { peer in
                                Button {
                                    service.invite(peer)
                                } label: {
                                    Text(peer.displayName)
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
                    }
                }
                HStack(spacing: 12) {
                    Button("Back", action: onBack)
                        .foregroundColor(.white.opacity(0.7))
                    Button("Diagnostics") { showDiagnostics = true }
                        .foregroundColor(.blue.opacity(0.8))
                }
                .font(.footnote)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showDiagnostics) {
            MPDiagnosticsView(lines: diag.lines)
        }
        .onAppear {
            MPDiag.shared.reset()
            service.startAdvertising()
            service.startBrowsing()
        }
        .onDisappear {
            service.stopBrowsing()
            // Keep advertising until match starts (Task 20 stops it then).
        }
    }
}
