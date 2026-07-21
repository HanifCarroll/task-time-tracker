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
    private var workLogStore: WorkLogStore?
    private var windowController: FloatingTimerWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let workLogStore = makeWorkLogStore()
        let state = TimerState(workLogStore: workLogStore)
        let windowController = FloatingTimerWindowController(state: state)
        self.state = state
        self.workLogStore = workLogStore
        self.windowController = windowController
        self.statusBarController = StatusBarController(state: state, windowController: windowController)
        windowController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.stopAllRunningTasks()
    }

    private func makeWorkLogStore() -> WorkLogStore? {
        do {
            let store = try WorkLogStore.makeDefault()
            try store.recoverOpenIntervals()
            return store
        } catch {
            fputs("Task Time Tracker persistence unavailable: \(error)\n", stderr)
            return nil
        }
    }
}
