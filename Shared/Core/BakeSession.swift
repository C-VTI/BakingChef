import Foundation

struct SessionStep: Codable, Hashable {
    var completedAt: Date?
    /// Intentional extra time (fridge pause, manual adjustment, +5 min) added while this step was the next one.
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

/// A running bake: the recipe, what has been checked off and the resulting timetable.
///
/// Timing rules
/// - The waiting time starts when a step is checked off: step *i + 1* is due at
///   "step *i* done + wait of step *i*" (+ intentional extra time).
/// - Steps further ahead are a forecast: expected work time + waiting time of every open step.
///   If the current step takes longer than its work time, the forecast moves along automatically.
/// - Checking off a step also checks off all steps before it; unchecking reopens all steps after it.
/// - Pause (fridge) freezes the countdown; resuming moves the next step by the pause length.
struct BakeSession: Codable, Hashable, Identifiable {
    var id: UUID
    var recipe: Recipe
    var multiplier: Double
    var startedAt: Date
    var steps: [SessionStep]
    /// Finish time as planned at the start (for the "+12 min" deviation).
    var originalFinishAt: Date
    var finishExtraSeconds: TimeInterval = 0
    var pausedAt: Date?

    init(recipe: Recipe, multiplier: Double = 1, start: Date = .now) {
        id = UUID()
        self.recipe = recipe
        self.multiplier = multiplier
        startedAt = start
        steps = recipe.steps.map { _ in SessionStep() }
        originalFinishAt = start.addingTimeInterval(TimeInterval(recipe.totalMinutes * 60))
    }

    // MARK: State

    var isPaused: Bool { pausedAt != nil }
    var nextIndex: Int? { steps.firstIndex { !$0.isDone } }
    var allStepsDone: Bool { nextIndex == nil }
    var doneCount: Int { steps.filter(\.isDone).count }

    /// "now", frozen while paused.
    func clock(_ now: Date) -> Date { pausedAt ?? now }

    /// Start of every step (done steps: when it was due) and the finish time, as expected at `now`.
    func schedule(at now: Date) -> (starts: [Date], finish: Date) {
        let next = nextIndex
        // A running pause will be added to the next step when resuming.
        let pending = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        var starts: [Date] = []
        var t = startedAt
        for (i, state) in steps.enumerated() {
            let step = recipe.steps[i]
            var start = t.addingTimeInterval(state.extraSeconds)
            if i == next { start += pending }
            starts.append(start)
            let done: Date
            if let completed = state.completedAt {
                done = completed
            } else {
                let expected = start.addingTimeInterval(TimeInterval(step.workMinutes * 60))
                // The step that is due right now cannot be done before now.
                done = i == next ? max(expected, now) : expected
            }
            t = done.addingTimeInterval(TimeInterval(step.waitMinutes * 60))
        }
        var finish = t.addingTimeInterval(finishExtraSeconds)
        if next == nil { finish += pending }
        return (starts, finish)
    }

    /// The next moment that matters: when the next open step is due, or the finish time.
    /// Fixed (does not depend on "now"), because everything before it is checked off.
    var nextDue: Date {
        let s = schedule(at: clock(.now))
        return nextIndex.map { s.starts[$0] } ?? s.finish
    }
    var nextTitle: String { nextIndex.map { recipe.steps[$0].title } ?? "Fertig" }
    /// Expected work time of the next step (0 when in the oven).
    var nextWorkSeconds: TimeInterval {
        nextIndex.map { TimeInterval(recipe.steps[$0].workMinutes * 60) } ?? 0
    }

    func finish(at now: Date) -> Date { schedule(at: now).finish }
    /// Seconds until `nextDue`; negative = the step is due (time since).
    func remaining(at now: Date) -> TimeInterval { nextDue.timeIntervalSince(clock(now)) }
    /// The next step is due and takes longer than its expected work time.
    func isOverdue(at now: Date) -> Bool {
        !isPaused && nextIndex != nil && -remaining(at: now) > max(60, nextWorkSeconds)
    }
    func isFinished(at now: Date) -> Bool { allStepsDone && !isPaused && now >= finish(at: now) }
    /// Deviation of the expected finish time from the original plan.
    func finishDeviation(at now: Date) -> TimeInterval { finish(at: now).timeIntervalSince(originalFinishAt) }

    // MARK: Mutations

    mutating func apply(_ action: SessionAction, at now: Date = .now) {
        switch action {
        case .complete(let i):
            guard steps.indices.contains(i), !steps[i].isDone else { return }
            resume(at: now)
            // Checking off a later step also checks off all skipped ones before it.
            for j in 0...i where !steps[j].isDone { steps[j].completedAt = now }
        case .uncomplete(let i):
            guard steps.indices.contains(i) else { return }
            // Jump back: this step and all after it are open again.
            for j in i..<steps.count {
                steps[j].completedAt = nil
                if j > i { steps[j].extraSeconds = 0 }
            }
            finishExtraSeconds = 0
        case .pause:
            pause(at: now)
        case .resume:
            resume(at: now)
        case .shift(let seconds):
            shift(by: seconds)
        }
    }

    mutating func toggle(_ i: Int, at now: Date = .now) {
        apply(steps[i].isDone ? .uncomplete(step: i) : .complete(step: i), at: now)
    }

    /// Moves the next step (and with it everything after it) by `delta`.
    mutating func shift(by delta: TimeInterval) {
        guard delta != 0 else { return }
        if let i = nextIndex { steps[i].extraSeconds += delta } else { finishExtraSeconds += delta }
    }

    mutating func pause(at now: Date = .now) {
        if pausedAt == nil { pausedAt = now }
    }

    mutating func resume(at now: Date = .now) {
        guard let p = pausedAt else { return }
        pausedAt = nil
        shift(by: max(0, now.timeIntervalSince(p)))
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
    ///
    /// Only the next step gets "in 5 min" / "now" notifications – later steps depend on when
    /// the current one is checked off. Custom reminders (e.g. preheat the oven) are planned
    /// for later steps too, using the forecast; they are rescheduled on every change.
    func notificationPlan(now: Date) -> [PlannedNotification] {
        guard !isPaused else { return [] }
        var out: [PlannedNotification] = []
        let ids = { (i: Int, kind: String) in "\(id.uuidString)-\(i)-\(kind)" }
        let count = steps.count
        let (starts, finish) = schedule(at: now)
        let next = nextIndex

        for (i, state) in steps.enumerated() where !state.isDone {
            let step = recipe.steps[i]
            let due = starts[i]
            let position = "Schritt \(i + 1) von \(count)"

            if let r = step.reminder, r.minutesBefore > 0 {
                let at = due.addingTimeInterval(-TimeInterval(r.minutesBefore * 60))
                if at > now {
                    out.append(.init(id: ids(i, "reminder"), date: at,
                                     title: r.text,
                                     body: "In ca. \(Format.duration(minutes: r.minutesBefore)): \(step.title)"))
                }
            }
            guard i == next else { continue }
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

        guard next == nil else { return out }
        let preFinish = finish.addingTimeInterval(-Self.preWarning)
        if preFinish > now {
            out.append(.init(id: ids(count, "pre"), date: preFinish,
                             title: "In 5 min fertig",
                             body: "\(recipe.name) – um \(Format.time(finish))"))
        }
        if finish > now {
            out.append(.init(id: ids(count, "due"), date: finish,
                             title: "Fertig! 🍞",
                             body: "\(recipe.name) ist fertig."))
        }
        return out
    }
}
