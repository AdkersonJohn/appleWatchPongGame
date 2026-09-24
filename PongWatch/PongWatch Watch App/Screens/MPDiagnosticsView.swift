import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Raw lobby event log, on the watch itself. A tester in another building has
/// no Mac to point Console at, so this is the only way their session's
/// evidence gets back to us — they scroll it and send a photo.
struct MPDiagnosticsView: View {
    let lines: [String]
    @State private var cleared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if lines.isEmpty {
                    Text("No events yet.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(color(for: line))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .navigationTitle("MP Log")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear") { MPDiag.shared.reset(); cleared = true }
            }
        }
        #if canImport(UIKit) && !os(watchOS)
        // The phone can hand the whole log back as text; the watch can only be
        // photographed, which is why the lines stay short.
        .safeAreaInset(edge: .bottom) {
            Button("Copy Log") { UIPasteboard.general.string = MPDiag.shared.shareText }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
        }
        #endif
    }

    /// Colour the two outcomes that matter so they're findable at a glance on
    /// a 40mm screen: red for a failed subsystem, green for a peer we showed.
    private func color(for line: String) -> Color {
        if line.contains("FAILED") || line.contains("WAITING") || line.contains("COLLISION") {
            return .red
        }
        if line.contains("PUBLISHED") || line.contains("· peer ") || line.contains("READY") {
            return .green
        }
        return .white.opacity(0.75)
    }
}
