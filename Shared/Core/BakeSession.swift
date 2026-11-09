import Foundation

struct SessionStep: Codable, Hashable {
    var dueAt: Date
    var completedAt: Date?
    /// Intentional extra time (fridge pause, manual shift) added while this step was the next one.
    /// Not counted as "delay" when suggesting a plan adjustment.
    var extraSeconds: TimeInterval = 0

    var isDone: Bool { completedAt != nil }
}

/// Actions that can be triggered from the iPhone, the Watch or a notification.
enum SessionAction: Codable, Hashable {
    case complete(step: Int)
    case uncomplete(step: Int)
    case pause
    case resume
    case shift(seconds: Double)
}

/// A running bake: the recipe, its timetable and what has been checked off.
///
/// Timing rules
/// - Step *i* is due at start + sum of the waits of all previous steps.
/// - Checking off late does NOT move the plan automatically; `suggestedShift` tells how far behind you are.
/// - Pause (fridge) freezes the countdown; resuming moves all open steps by the pause length.
struct BakeSession: Codable, Hashable, Identifiable {
    var id: UUID
    var recipe: Recipe
    var multiplier: Double
    var startedAt: Date
    var steps: [SessionStep]
    var finishAt: Date
    var originalFinishAt: Date
    var finishExtraSeconds: TimeInterval = 0
    var pausedAt: Date?

    init(recipe: Recipe, multiplier: Double = 1, start: Date = .now) {
        id = UUID()
        self.recipe = recipe
        self.multiplier = multiplier
        startedAt = start
        var t = start
        var list: [SessionStep] = []
        for step in recipe.steps {
            list.append(SessionStep(dueAt: t))
            t += TimeInterval(step.waitMinutes * 60)
        }
        steps = list
        finishAt = t
        originalFinishAt = t
    }

    // MARK: State

    var isPaused: Bool { pausedAt != nil }
    var nextIndex: Int? { steps.firstIndex { !$0.isDone } }
    var allStepsDone: Bool { nextIndex == nil }
    var doneCount: Int { steps.filter(\.isDone).count }

    /// The next moment that matters: the next open step, or the finish time.
    var nextDue: Date { nextIndex.map { steps[$0].dueAt } ?? finishAt }
    var nextTitle: String { nextIndex.map { recipe.steps[$0].title } ?? "Fertig" }

    /// "now", frozen while paused.
    func clock(_ now: Date) -> Date { pausedAt ?? now }
    /// Seconds until `nextDue`; negative = overdue.
    func remaining(at now: Date) -> TimeInterval { nextDue.timeIntervalSince(clock(now)) }
    func isFinished(at now: Date) -> Bool { allStepsDone && !isPaused && now >= finishAt }
    /// Total deviation of the finish time from the original plan.
    var finishDeviation: TimeInterval { finishAt.timeIntervalSince(originalFinishAt) }

    /// How far the next step should move so that it is due exactly
    /// "previous completion + waiting time" (+ intentional extra time).
    /// Positive = you are behind, negative = ahead. `nil` when below one minute.
    var suggestedShift: TimeInterval? {
        guard !isPaused else { return nil }
        let next = nextIndex ?? steps.count
        guard next > 0, let done = steps[next - 1].completedAt else { return nil }
        let extra = next < steps.count ? steps[next].extraSeconds : finishExtraSeconds
        let ideal = done + TimeInterval(recipe.steps[next - 1].waitMinutes * 60) + extra
        let delta = (ideal.timeIntervalSince(nextDue) / 60).rounded(.towardZero) * 60
        return abs(delta) >= 60 ? delta : nil
    }

    // MARK: Mutations

    mutating func apply(_ action: SessionAction, at now: Date = .now) {
        switch action {
        case .complete(let i):
            guard steps.indices.contains(i), !steps[i].isDone else { return }
            steps[i].completedAt = now
        case .uncomplete(let i):
            guard steps.indices.contains(i) else { return }
            steps[i].completedAt = nil
        case .pause:
            pause(at: now)
        case .resume:
            resume(at: now)
        case .shift(let seconds):
            shift(by: seconds, intentional: true)
        }
    }

    mutating func toggle(_ i: Int, at now: Date = .now) {
        apply(steps[i].isDone ? .uncomplete(step: i) : .complete(step: i), at: now)
    }

    /// Moves all open steps and the finish time.
    /// - Parameter intentional: `true` for manual shifts / pauses (wanted extra time),
    ///   `false` when applying `suggestedShift` (catching up with reality).
    mutating func shift(by delta: TimeInterval, intentional: Bool) {
        guard delta != 0 else { return }
        for i in steps.indices where !steps[i].isDone { steps[i].dueAt += delta }
        finishAt += delta
        guard intentional else { return }
        if let i = nextIndex { steps[i].extraSeconds += delta } else { finishExtraSeconds += delta }
    }

    /// Sets the countdown to the next step to `remaining` and moves all later steps accordingly.
    mutating func setRemaining(_ remaining: TimeInterval, at now: Date = .now) {
        shift(by: clock(now).addingTimeInterval(remaining).timeIntervalSince(nextDue), intentional: true)
    }

    mutating func pause(at now: Date = .now) {
        if pausedAt == nil { pausedAt = now }
    }

    mutating func resume(at now: Date = .now) {
        guard let p = pausedAt else { return }
        pausedAt = nil
        shift(by: max(0, now.timeIntervalSince(p)), intentional: true)
    }

    // MARK: Notifications

    struct PlannedNotification: Hashable {
        var id: String
        var date: Date
        var title: String
        var body: String
        /// Set for "step is due" notifications (they get an "Erledigt" action).
        var stepIndex: Int?
    }

    static let preWarning: TimeInterval = 5 * 60

    func notificationIDs(forStep i: Int) -> [String] {
        ["reminder", "pre", "due"].map { "\(id.uuidString)-\(i)-\($0)" }
    }

    /// All notifications that should be pending right now. Empty while paused.
    func notificationPlan(now: Date) -> [PlannedNotification] {
        guard !isPaused else { return [] }
        var out: [PlannedNotification] = []
        let ids = { (i: Int, kind: String) in "\(id.uuidString)-\(i)-\(kind)" }
        let count = steps.count

        for (i, state) in steps.enumerated() where !state.isDone {
            let step = recipe.steps[i]
            let due = state.dueAt
            let position = "Schritt \(i + 1) von \(count)"

            if let r = step.reminder, r.minutesBefore > 0 {
                let at = due.addingTimeInterval(-TimeInterval(r.minutesBefore * 60))
                if at > now {
                    out.append(.init(id: ids(i, "reminder"), date: at,
                                     title: r.text,
                                     body: "In \(Format.duration(minutes: r.minutesBefore)): \(step.title)"))
                }
            }
            let pre = due.addingTimeInterval(-Self.preWarning)
            if pre > now {
                out.append(.init(id: ids(i, "pre"), date: pre,
                                 title: "In 5 min: \(step.title)",
                                 body: "Um \(Format.time(due)) · \(position)"))
            }
            if due > now {
                let details = step.ingredients.isEmpty
                    ? (step.note ?? position)
                    : step.ingredientsText(multiplier: multiplier)
                out.append(.init(id: ids(i, "due"), date: due,
                                 title: "Jetzt: \(step.title)",
                                 body: details, stepIndex: i))
            }
        }

        let preFinish = finishAt.addingTimeInterval(-Self.preWarning)
        if preFinish > now {
            out.append(.init(id: ids(count, "pre"), date: preFinish,
                             title: "In 5 min fertig",
                             body: "\(recipe.name) – um \(Format.time(finishAt))"))
        }
        if finishAt > now {
            out.append(.init(id: ids(count, "due"), date: finishAt,
                             title: "Fertig! 🍞",
                             body: "\(recipe.name) ist fertig."))
        }
        return out
    }
}
