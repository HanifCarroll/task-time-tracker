import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let state: TimerState
    private let windowController: FloatingTimerWindowController
    private let statusItem: NSStatusItem
    private let runningFont: NSFont
    private let idleFont: NSFont
    private let idleImage: NSImage?
    private var cancellables: Set<AnyCancellable> = []

    init(state: TimerState, windowController: FloatingTimerWindowController) {
        self.state = state
        self.windowController = windowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.runningFont = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        self.idleFont = .systemFont(ofSize: NSFont.systemFontSize)
        self.idleImage = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Task Time Tracker")
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

        let taskItem = NSMenuItem(title: state.menuBarTitle, action: nil, keyEquivalent: "")
        taskItem.isEnabled = false
        menu.addItem(taskItem)

        let summaryItem = NSMenuItem(title: state.taskSummary, action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
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

        state.tickPublisher
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.windowController.isVisible else { return }
                    self.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        if state.hasRunningTasks, !windowController.isVisible {
            let title = state.statusBarTitle
            if button.image != nil {
                button.image = nil
            }
            if button.title != title {
                button.title = title
            }
            if button.font !== runningFont {
                button.font = runningFont
            }
        } else {
            if !button.title.isEmpty {
                button.title = ""
            }
            if button.font !== idleFont {
                button.font = idleFont
            }
            if button.image !== idleImage {
                button.image = idleImage
            }
        }
    }
}
