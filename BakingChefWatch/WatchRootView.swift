import SwiftUI

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            if let session = model.session {
                WatchSessionView(session: session)
            } else {
                ContentUnavailableView("No bake running",
                                       systemImage: "timer",
                                       description: Text("Start a recipe on your iPhone."))
            }
        }
    }
}

private struct WatchSessionView: View {
    @Environment(WatchModel.self) private var model
    let session: BakeSession

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(session.isPaused ? .blue : .secondary)
                    Text(session.nextTitle)
                        .font(.headline)
                    SessionCountdown(session: session)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    if let next = session.nextIndex {
                        ForEach(session.recipe.steps[next].ingredients, id: \.self) { ingredient in
                            Text(ingredient.text(multiplier: session.multiplier))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if session.isPaused {
                    Button { model.send(.resume) } label: { Label("Resume", systemImage: "play.fill") }
                        .tint(.orange)
                } else {
                    if let next = session.nextIndex {
                        Button { model.send(.complete(step: next)) } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                    Button { model.send(.shift(seconds: 5 * 60)) } label: {
                        Label("+5 min", systemImage: "plus.circle")
                    }
                    Button { model.send(.pause) } label: { Label("Pause", systemImage: "snowflake") }
                }
            }

            Section("Steps") {
                let schedule = session.schedule(at: .now)
                ForEach(session.steps.indices, id: \.self) { i in
                    HStack {
                        Image(systemName: session.steps[i].isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(session.steps[i].isDone ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(session.recipe.steps[i].title).font(.footnote)
                            Text(Format.time(session.steps[i].completedAt ?? schedule.starts[i]))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Image(systemName: "flag.checkered")
                    Text("Ready approx. \(Format.time(schedule.finish))").font(.footnote)
                }
            }
        }
        .navigationTitle(session.recipe.name)
    }

    private var status: String {
        if session.isPaused { return String(localized: "Paused") }
        if let i = session.nextIndex { return String(localized: "Step \(i + 1)/\(session.steps.count)") }
        return String(localized: "In the oven")
    }
}
