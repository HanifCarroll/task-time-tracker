import SwiftUI

@main
struct TaskTimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state: TimerState
    @StateObject private var windowController: FloatingTimerWindowController

    init() {
        let state = TimerState()
        _state = StateObject(wrappedValue: state)
        _windowController = StateObject(wrappedValue: FloatingTimerWindowController(state: state))
    }

    var body: some Scene {
        MenuBarExtra {
            Text(state.currentTaskName)
                .font(.headline)
            Text(state.formattedTime(state.displaySeconds))
                .font(.system(.body, design: .monospaced))

            Divider()

            Button(windowController.isVisible ? "Hide Timer" : "Show Timer") {
                windowController.toggle()
            }
            .keyboardShortcut("t")

            Divider()

            Button(state.isRunning ? "Pause" : "Start") {
                state.toggleRunning()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Reset") {
                state.reset()
            }

            Picker("Mode", selection: $state.mode) {
                ForEach(TimerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("Keep On Top", isOn: $state.keepOnTop)

            Divider()

            Button("Quit Task Time Tracker") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            if state.isRunning {
                Text(state.formattedTime(state.displaySeconds))
                    .monospacedDigit()
            } else {
                Image(systemName: "timer.circle")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
