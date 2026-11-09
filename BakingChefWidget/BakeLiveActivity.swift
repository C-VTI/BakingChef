import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BakingChefWidgetBundle: WidgetBundle {
    var body: some Widget {
        BakeLiveActivity()
    }
}

struct BakeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BakeActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.detail, systemImage: context.state.pausedAt == nil ? "timer" : "snowflake")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("Fertig")
                            Text(context.state.finishAt, style: .time)
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.state.pausedAt == nil ? "timer" : "snowflake")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                CountdownText(state: context.state)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: BakeActivityAttributes
    let state: BakeActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(attributes.recipeName, systemImage: "birthday.cake")
                Spacer()
                Text(state.detail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.pausedAt == nil ? "Nächster Schritt" : "Pausiert seit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
                CountdownText(state: state)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            if state.pausedAt == nil {
                HStack(spacing: 4) {
                    Image(systemName: "flag.checkered")
                    Text("Fertig ca.")
                    Text(state.finishAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

/// Counts down to the next step; while paused it counts the pause duration up.
private struct CountdownText: View {
    let state: BakeActivityAttributes.ContentState

    var body: some View {
        if let paused = state.pausedAt {
            Text(paused, style: .timer)
        } else {
            Text(timerInterval: min(state.updatedAt, state.dueAt)...state.dueAt, countsDown: true)
        }
    }
}
