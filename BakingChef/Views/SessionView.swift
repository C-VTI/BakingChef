import SwiftUI

struct SessionView: View {
    @Environment(AppModel.self) private var model
    let session: BakeSession
    @State private var showAdjust = false
    @State private var confirmEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let schedule = session.schedule(at: now)
            List {
                Section { StatusCard(session: session, now: now, finish: schedule.finish,
                                     showAdjust: $showAdjust) }

                Section {
                    ForEach(session.steps.indices, id: \.self) { i in
                        SessionStepRow(session: session, index: i, start: schedule.starts[i], now: now)
                    }
                    FinishRow(finish: schedule.finish, now: now)
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Tapping a step checks it off together with all steps before it. Tapping a completed step jumps back to it.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmEnd = true
                    } label: {
                        Label("End bake", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(session.recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("End bake?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End", role: .destructive) { model.endSession() }
        } message: {
            Text("All reminders will be deleted.")
        }
        .sheet(isPresented: $showAdjust) {
            AdjustTimeSheet(session: session)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Status card (big countdown + main actions)

private struct StatusCard: View {
    @Environment(AppModel.self) private var model
    let session: BakeSession
    let now: Date
    let finish: Date
    @Binding var showAdjust: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.isFinished(at: now) {
                finishedContent
            } else {
                runningContent
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var finishedContent: some View {
        Text("Ready! 🍞").font(.largeTitle.bold())
        Text("Enjoy!").foregroundStyle(.secondary)
        Button {
            model.endSession()
        } label: {
            Label("Finish", systemImage: "checkmark")
                .font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder private var runningContent: some View {
        let remaining = session.remaining(at: now)
        let next = session.nextIndex
        let isDue = remaining < 0 && !session.isPaused && next != nil
        let overdue = session.isOverdue(at: now)
        let deviation = session.finishDeviation(at: now)

        HStack {
            if session.isPaused {
                Label("Paused for \(Format.countdown(now.timeIntervalSince(session.pausedAt!)))",
                      systemImage: "snowflake")
                    .foregroundStyle(.blue)
            } else if let next {
                if isDue {
                    Text("Now · \(next + 1)/\(session.steps.count)")
                } else {
                    Text("Next step · \(next + 1)/\(session.steps.count)")
                }
            } else {
                Text("In the oven")
            }
            Spacer()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)

        Text(session.nextTitle)
            .font(.title2.bold())

        HStack(alignment: .firstTextBaseline) {
            Text((remaining < 0 ? "+" : "") + Format.countdown(remaining))
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(overdue ? .red : (isDue ? .orange : .primary))
                .contentTransition(.numericText(countsDown: true))
                .onTapGesture { if !session.isPaused { showAdjust = true } }
            Spacer()
        }
        if overdue {
            Text("overdue – waiting time starts with “Done”").font(.caption).foregroundStyle(.red)
        } else if isDue {
            Group {
                if session.nextWorkSeconds > 0 {
                    Text("Do it now · approx. \(Format.duration(seconds: session.nextWorkSeconds))")
                } else {
                    Text("Do it now")
                }
            }
            .font(.caption).foregroundStyle(.orange)
        }

        VStack(alignment: .leading, spacing: 2) {
            if isDue {
                Text("Due since \(Format.dayTime(session.nextDue, relativeTo: now))")
            } else {
                Text("Due at \(Format.dayTime(session.nextDue, relativeTo: now))")
            }
            HStack(spacing: 4) {
                Text("Ready approx. \(Format.dayTime(finish, relativeTo: now))")
                if abs(deviation) >= 60 {
                    Text("(\(Format.signedMinutes(deviation)))")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()

        if let next {
            IngredientList(ingredients: session.recipe.steps[next].ingredients,
                           multiplier: session.multiplier)
        }

        if session.isPaused {
            Button {
                model.apply(.resume)
            } label: {
                Label("Resume", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            if let next {
                Button {
                    model.apply(.complete(step: next))
                } label: {
                    Label("Done", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            HStack {
                Button {
                    model.apply(.pause)
                } label: {
                    Label("Pause", systemImage: "snowflake").frame(maxWidth: .infinity)
                }
                Button {
                    showAdjust = true
                } label: {
                    Label("Adjust time", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

// MARK: - Step rows

private struct SessionStepRow: View {
    @Environment(AppModel.self) private var model
    let session: BakeSession
    let index: Int
    /// Planned / expected start of this step.
    let start: Date
    let now: Date

    var body: some View {
        let state = session.steps[index]
        let step = session.recipe.steps[index]
        let isNext = index == session.nextIndex

        Button {
            model.mutate { $0.toggle(index) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: state.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(state.isDone ? Color.green : (isNext ? Color.accentColor : Color.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(isNext ? .body.bold() : .body)
                        .strikethrough(state.isDone)
                        .foregroundStyle(state.isDone ? .secondary : .primary)
                    if let detail = detail(step) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let done = state.completedAt {
                        Text(Format.time(done))
                    } else {
                        // Only the next step has a fixed time, later ones are a forecast.
                        Text((isNext ? "" : "~") + Format.dayTime(start, relativeTo: now))
                    }
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detail(_ step: RecipeStep) -> String? {
        var parts: [String] = []
        if step.workMinutes > 0 { parts.append(String(localized: "approx. \(Format.duration(minutes: step.workMinutes))")) }
        if step.waitMinutes > 0 { parts.append(String(localized: "then \(Format.duration(minutes: step.waitMinutes))")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct FinishRow: View {
    let finish: Date
    let now: Date

    var body: some View {
        HStack {
            Label("Ready", systemImage: "flag.checkered").font(.headline)
            Spacer()
            Text(Format.dayTime(finish, relativeTo: now)).font(.headline).monospacedDigit()
        }
    }
}
