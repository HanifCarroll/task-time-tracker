import SwiftUI

@main
struct TaskTimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: TimerState?
    private var windowController: FloatingTimerWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let state = TimerState()
        let windowController = FloatingTimerWindowController(state: state)
        self.state = state
        self.windowController = windowController
        self.statusBarController = StatusBarController(state: state, windowController: windowController)
    }
}
