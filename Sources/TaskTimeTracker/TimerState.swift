import Foundation
import SwiftUI

enum TimerMode: String, CaseIterable, Identifiable {
    case countUp = "Free Time"
    case countdown = "Countdown"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .countUp: "stopwatch"
        case .countdown: "timer"
        }
    }
}

struct TrackedTask: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var seconds: Int
    var completedAt: Date
}

@MainActor
final class TimerState: ObservableObject {
    @Published var taskTitle = "Deep work"
    @Published var mode: TimerMode = .countUp {
        didSet {
            guard mode != oldValue else { return }
            pause()
            elapsedSeconds = 0
        }
    }
    @Published var countdownSeconds = 25 * 60
    @Published var elapsedSeconds = 0
    @Published var isRunning = false
    @Published var keepOnTop = true
    @Published var completedTasks: [TrackedTask] = []

    private var timer: Timer?

    var displaySeconds: Int {
        switch mode {
        case .countUp:
            elapsedSeconds
        case .countdown:
            max(countdownSeconds - elapsedSeconds, 0)
        }
    }

    var progress: Double {
        guard mode == .countdown else { return 0 }
        let total = max(countdownSeconds, 1)
        return min(Double(elapsedSeconds) / Double(total), 1)
    }

    var currentTaskName: String {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled task" : trimmed
    }

    var menuBarTitle: String {
        "\(shortTaskName) · \(formattedTime(displaySeconds))"
    }

    private var shortTaskName: String {
        let name = currentTaskName
        guard name.count > 18 else { return name }
        return "\(name.prefix(15))…"
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        elapsedSeconds = 0
    }

    func setStoppedCountdownMinutes(_ minutes: Int) {
        guard mode == .countdown, !isRunning else { return }
        countdownSeconds = max(minutes, 1) * 60
        elapsedSeconds = 0
    }

    func completeTask() {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Untitled task" : trimmed
        let secondsSpent: Int
        switch mode {
        case .countUp:
            secondsSpent = elapsedSeconds
        case .countdown:
            secondsSpent = min(elapsedSeconds, countdownSeconds)
        }

        guard secondsSpent > 0 else { return }
        completedTasks.insert(
            TrackedTask(title: title, seconds: secondsSpent, completedAt: Date()),
            at: 0
        )
        reset()
    }

    func formattedTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func tick() {
        elapsedSeconds += 1
        if mode == .countdown, elapsedSeconds >= countdownSeconds {
            NSSound.beep()
            pause()
        }
    }
}
