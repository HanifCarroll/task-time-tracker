import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let state: TimerState
    private let windowController: FloatingTimerWindowController
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(state: TimerState, windowController: FloatingTimerWindowController) {
        self.state = state
        self.windowController = windowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(openTimerWindow)
        }

        bindUpdates()
        updateStatusItem()
    }

    @objc private func openTimerWindow() {
        windowController.show()
    }

    private func bindUpdates() {
        state.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)

        windowController.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        if state.isRunning, !windowController.isVisible {
            button.image = nil
            button.title = state.formattedTime(state.displaySeconds)
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        } else {
            button.title = ""
            button.font = .systemFont(ofSize: NSFont.systemFontSize)
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Task Time Tracker")
        }
    }
}
