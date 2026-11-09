import SwiftUI
import UIKit

/// Change the timetable with an iOS timer wheel:
/// - "Restzeit": set the countdown to the next step directly
/// - "Verschieben": move all open steps later/earlier by a duration
struct AdjustTimeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: BakeSession

    private enum Mode: String, CaseIterable, Identifiable {
        case remaining = "Restzeit setzen"
        case shift = "Verschieben"
        var id: Self { self }
    }

    @State private var mode: Mode = .remaining
    @State private var later = true
    @State private var duration: TimeInterval

    init(session: BakeSession) {
        self.session = session
        _duration = State(initialValue: Self.wheelValue(session.remaining(at: .now)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Modus", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .shift {
                    Picker("Richtung", selection: $later) {
                        Text("Später").tag(true)
                        Text("Früher").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                CountdownWheel(duration: $duration)
                    .frame(height: 180)

                if mode == .shift {
                    HStack {
                        ForEach([5, 10, 15, 30], id: \.self) { minutes in
                            Button("\(minutes) min") { duration = TimeInterval(minutes * 60) }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                VStack(spacing: 2) {
                    Text("\(session.nextTitle): \(Format.dayTime(session.nextDue.addingTimeInterval(delta)))")
                    Text("Fertig ca. \(Format.dayTime(session.finishAt.addingTimeInterval(delta)))")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(mode == .remaining ? "Nächster Schritt in" : "Plan verschieben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        let d = delta
                        model.mutate { $0.shift(by: d, intentional: true) }
                        dismiss()
                    }
                    .bold()
                }
            }
            .onChange(of: mode) { _, newMode in
                duration = newMode == .remaining
                    ? Self.wheelValue(session.remaining(at: .now))
                    : 5 * 60
            }
        }
    }

    /// Shift that will be applied to all open steps.
    private var delta: TimeInterval {
        switch mode {
        case .remaining:
            return Date.now.addingTimeInterval(duration).timeIntervalSince(session.nextDue)
        case .shift:
            return later ? duration : -duration
        }
    }

    /// The wheel works in whole minutes, 1 min … 23 h 59 min.
    private static func wheelValue(_ seconds: TimeInterval) -> TimeInterval {
        min(max(60, (seconds / 60).rounded() * 60), 23 * 3600 + 59 * 60)
    }
}

/// The native iOS timer wheel (hours + minutes), as in the Clock app.
struct CountdownWheel: UIViewRepresentable {
    @Binding var duration: TimeInterval

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .countDownTimer
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        // Setting the value async works around a UIKit bug where the first change is not reported.
        let initial = duration
        DispatchQueue.main.async { picker.countDownDuration = initial }
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        if abs(picker.countDownDuration - duration) >= 1 {
            picker.countDownDuration = duration
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: CountdownWheel
        init(parent: CountdownWheel) { self.parent = parent }

        @objc func changed(_ picker: UIDatePicker) {
            parent.duration = picker.countDownDuration
        }
    }
}
