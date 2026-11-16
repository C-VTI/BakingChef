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
            LockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.detail, systemImage: context.state.pausedAt == nil ? "timer" : "snowflake")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state, isStale: context.isStale)
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
                            Text("Ready")
                            Text(context.state.finishAt, style: .time)
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.state.pausedAt == nil ? "timer" : "snowflake")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                CountdownText(state: context.state, isStale: context.isStale)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: context.state.pausedAt == nil ? "timer" : "snowflake")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: BakeActivityAttributes
    let state: BakeActivityAttributes.ContentState
    let isStale: Bool

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
                    Text(state.pausedAt == nil ? "Next step" : "Then")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
                CountdownText(state: state, isStale: isStale)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            if state.pausedAt == nil {
                HStack(spacing: 4) {
                    Image(systemName: "flag.checkered")
                    Text("Ready approx.")
                    Text(state.finishAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

/// Counts down to the next step. Once it is due it counts the overdue time up ("+m:ss").
/// In the fridge (paused) there is no counter at all.
private struct CountdownText: View {
    let state: BakeActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if state.pausedAt != nil {
            Image(systemName: "snowflake")
                .foregroundStyle(.blue)
        } else if isStale || state.dueAt <= state.updatedAt {
            // `.timer` counts up for dates in the past.
            (Text(verbatim: "+") + Text(state.dueAt, style: .timer))
                .foregroundStyle(.red)
        } else {
            Text(timerInterval: state.updatedAt...state.dueAt, countsDown: true)
        }
    }
}
