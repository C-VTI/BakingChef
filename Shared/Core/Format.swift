import Foundation

/// Formatting helpers shared by iPhone, Watch and the Live Activity.
enum Format {
    /// 40 → "40", 67.5 → "67.5" (decimal separator follows the device locale)
    static func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    static func multiplier(_ value: Double) -> String { "\(amount(value))×" }

    /// 240 → "4 h", 90 → "1 h 30 min", 20 → "20 min"
    static func duration(minutes: Int) -> String {
        let h = abs(minutes) / 60, m = abs(minutes) % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }

    static func duration(seconds: TimeInterval) -> String {
        duration(minutes: Int((abs(seconds) / 60).rounded()))
    }

    /// Countdown text without sign: "1:05:09" or "4:09".
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = seconds >= 0 ? Int(seconds.rounded(.up)) : Int((-seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "+5 min" / "−5 min"
    static func signedMinutes(_ seconds: TimeInterval) -> String {
        "\(seconds < 0 ? "−" : "+")\(duration(seconds: seconds))"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Clock time, prefixed with the weekday when it is not today.
    static func dayTime(_ date: Date, relativeTo now: Date = .now) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? time(date)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
