import SwiftUI

/// Live countdown to the next due moment. Shows "+m:ss" in red when overdue.
struct SessionCountdown: View {
    let session: BakeSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = session.remaining(at: context.date)
            Text((remaining < 0 ? "+" : "") + Format.countdown(remaining))
                .monospacedDigit()
                .foregroundStyle(remaining < 0 && !session.isPaused ? Color.red : Color.primary)
                .contentTransition(.numericText(countsDown: true))
        }
    }
}
