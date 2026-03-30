import SwiftUI

struct MenuBarIconView: View {
    let pendingCount: Int
    let serverRunning: Bool
    let oldestRequestDate: Date?

    private static let timeout: TimeInterval = Constants.requestTimeout

    @State private var remaining: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: Double {
        guard remaining > 0 else { return 0 }
        return remaining / Self.timeout
    }

    var body: some View {
        HStack(spacing: 2) {
            if !serverRunning {
                Image(systemName: "shield.slash")
            } else if pendingCount > 0 {
                Image(systemName: "exclamationmark.shield")

                Text(remainingLabel)
                    .monospacedDigit()
                    .font(.caption2)
            } else {
                Image(systemName: "checkmark.shield")
            }
        }
        .onReceive(timer) { _ in
            updateRemaining()
        }
        .onChange(of: oldestRequestDate) {
            updateRemaining()
        }
    }

    private var remainingLabel: String {
        let secs = Int(remaining)
        return "\(secs)s"
    }

    private func updateRemaining() {
        if let date = oldestRequestDate {
            remaining = max(0, Self.timeout - Date().timeIntervalSince(date))
        } else {
            remaining = 0
        }
    }
}
