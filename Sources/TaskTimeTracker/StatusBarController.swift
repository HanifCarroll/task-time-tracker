import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
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
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        bindUpdates()
        updateStatusItem()
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            windowController.show()
        }
    }

    @objc private func showTimerWindow() {
        windowController.show()
    }

    @objc private func hideTimerWindow() {
        windowController.hide()
    }

    @objc private func toggleRunning() {
        state.toggleRunning()
    }

    @objc private func resetTimer() {
        state.reset()
    }

    @objc private func selectCountUpMode() {
        state.mode = .countUp
    }

    @objc private func selectCountdownMode() {
        state.mode = .countdown
    }

    @objc private func toggleKeepOnTop() {
        state.keepOnTop.toggle()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }

        let menu = NSMenu()
        menu.delegate = self

        let taskItem = NSMenuItem(title: state.currentTaskName, action: nil, keyEquivalent: "")
        taskItem.isEnabled = false
        menu.addItem(taskItem)

        let timeItem = NSMenuItem(title: state.formattedTime(state.displaySeconds), action: nil, keyEquivalent: "")
        timeItem.isEnabled = false
        menu.addItem(timeItem)
        menu.addItem(.separator())

        if windowController.isVisible {
            menu.addItem(menuItem("Hide Timer", action: #selector(hideTimerWindow), keyEquivalent: "t"))
        } else {
            menu.addItem(menuItem("Show Timer", action: #selector(showTimerWindow), keyEquivalent: "t"))
        }
        menu.addItem(.separator())

        menu.addItem(menuItem(state.isRunning ? "Pause" : "Start", action: #selector(toggleRunning), keyEquivalent: " "))
        menu.addItem(menuItem("Reset", action: #selector(resetTimer)))

        let modeMenu = NSMenu()
        let countUpItem = menuItem(TimerMode.countUp.rawValue, action: #selector(selectCountUpMode))
        countUpItem.state = state.mode == .countUp ? .on : .off
        modeMenu.addItem(countUpItem)
        let countdownItem = menuItem(TimerMode.countdown.rawValue, action: #selector(selectCountdownMode))
        countdownItem.state = state.mode == .countdown ? .on : .off
        modeMenu.addItem(countdownItem)

        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let keepOnTopItem = menuItem("Keep On Top", action: #selector(toggleKeepOnTop))
        keepOnTopItem.state = state.keepOnTop ? .on : .off
        menu.addItem(keepOnTopItem)

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Task Time Tracker", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
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
