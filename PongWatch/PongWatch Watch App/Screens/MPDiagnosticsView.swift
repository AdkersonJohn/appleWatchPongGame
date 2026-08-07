import SwiftUI

/// Raw lobby event log, on the watch itself. A tester in another building has
/// no Mac to point Console at, so this is the only way their session's
/// evidence gets back to us — they scroll it and send a photo.
struct MPDiagnosticsView: View {
    let lines: [String]

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
