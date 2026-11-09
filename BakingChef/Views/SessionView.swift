import SwiftUI

struct SessionView: View {
    @Environment(AppModel.self) private var model
    let session: BakeSession
    @State private var showAdjust = false
    @State private var confirmEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            List {
                Section { StatusCard(session: session, now: now, showAdjust: $showAdjust) }

                if let delta = session.suggestedShift {
                    Section { DelayBanner(delta: delta) }
                }

                Section("Schritte") {
                    ForEach(session.steps.indices, id: \.self) { i in
                        SessionStepRow(session: session, index: i, now: now)
                    }
                    FinishRow(session: session)
                }
            }
        }
        .navigationTitle(session.recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Backvorgang beenden", systemImage: "xmark.circle", role: .destructive) {
                        confirmEnd = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Backvorgang beenden?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Beenden", role: .destructive) { model.endSession() }
        } message: {
            Text("Alle Erinnerungen werden gelöscht.")
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
        Text("Fertig! 🍞").font(.largeTitle.bold())
        Text("Guten Appetit.").foregroundStyle(.secondary)
        Button {
            model.endSession()
        } label: {
            Label("Abschliessen", systemImage: "checkmark")
                .font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder private var runningContent: some View {
        let remaining = session.remaining(at: now)
        let next = session.nextIndex

        HStack {
            if session.isPaused {
                Label("Pausiert seit \(Format.countdown(now.timeIntervalSince(session.pausedAt!)))",
                      systemImage: "snowflake")
                    .foregroundStyle(.blue)
            } else if let next {
                Text("Nächster Schritt · \(next + 1)/\(session.steps.count)")
            } else {
                Text("Im Ofen")
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
                .foregroundStyle(remaining < 0 && !session.isPaused ? .red : .primary)
                .contentTransition(.numericText(countsDown: true))
                .onTapGesture { if !session.isPaused { showAdjust = true } }
            Spacer()
        }
        if remaining < 0 && !session.isPaused {
            Text("überfällig").font(.caption).foregroundStyle(.red)
        }

        VStack(alignment: .leading, spacing: 2) {
            Text("Fällig um \(Format.dayTime(session.nextDue, relativeTo: now))")
            HStack(spacing: 4) {
                Text("Fertig ca. \(Format.dayTime(session.finishAt, relativeTo: now))")
                if abs(session.finishDeviation) >= 60 {
                    Text("(\(Format.signedMinutes(session.finishDeviation)))")
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
                Label("Weiter", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            if let next {
                Button {
                    model.apply(.complete(step: next))
                } label: {
                    Label("Erledigt", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity)
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
                    Label("Zeit anpassen", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

// MARK: - Delay banner

private struct DelayBanner: View {
    @Environment(AppModel.self) private var model
    let delta: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(delta > 0
                  ? "Du bist \(Format.duration(seconds: delta)) später dran als geplant."
                  : "Du bist \(Format.duration(seconds: delta)) früher dran als geplant.",
                  systemImage: delta > 0 ? "tortoise" : "hare")
                .font(.subheadline)
            Button("Plan \(Format.signedMinutes(delta)) verschieben") {
                model.mutate { $0.shift(by: delta, intentional: false) }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Step rows

private struct SessionStepRow: View {
    @Environment(AppModel.self) private var model
    let session: BakeSession
    let index: Int
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
                    if step.waitMinutes > 0 {
                        Text("danach \(Format.duration(minutes: step.waitMinutes))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let done = state.completedAt {
                        Text(Format.time(done))
                        let diff = done.timeIntervalSince(state.dueAt)
                        if abs(diff) >= 60 {
                            Text(Format.signedMinutes(diff)).font(.caption)
                                .foregroundStyle(diff > 0 ? .orange : .secondary)
                        }
                    } else {
                        Text(Format.dayTime(state.dueAt, relativeTo: now))
                    }
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FinishRow: View {
    let session: BakeSession

    var body: some View {
        HStack {
            Label("Fertig", systemImage: "flag.checkered").font(.headline)
            Spacer()
            Text(Format.dayTime(session.finishAt)).font(.headline).monospacedDigit()
        }
    }
}
