import AppKit
import SwiftUI

@MainActor
final class FloatingTimerWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false

    private static let legacyDefaultSize = NSSize(width: 220, height: 132)
    private static let defaultSize = NSSize(width: 320, height: 104)
    private static let savedWidthKey = "FloatingTimerWindow.width"
    private static let savedHeightKey = "FloatingTimerWindow.height"

    private let state: TimerState
    private var panel: NSPanel?

    init(state: TimerState) {
        self.state = state
        super.init()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        applyLevel()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func applyLevel() {
        panel?.level = state.keepOnTop ? .floating : .normal
    }

    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        saveSize(panel.frame.size)
    }

    private func makePanel() -> NSPanel {
        let size = savedSize()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.title = "Task Time Tracker"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.minSize = Self.defaultSize
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: TimerPanelView(state: state, windowController: self))
        positionInTopRight(panel)
        return panel
    }

    private func savedSize() -> NSSize {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: Self.savedWidthKey)
        let height = defaults.double(forKey: Self.savedHeightKey)

        guard width >= Self.defaultSize.width, height >= Self.defaultSize.height else {
            return Self.defaultSize
        }

        if width == Self.legacyDefaultSize.width, height == Self.legacyDefaultSize.height {
            return Self.defaultSize
        }

        return NSSize(width: width, height: height)
    }

    private func saveSize(_ size: NSSize) {
        UserDefaults.standard.set(size.width, forKey: Self.savedWidthKey)
        UserDefaults.standard.set(size.height, forKey: Self.savedHeightKey)
    }

    private func positionInTopRight(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            panel.center()
            return
        }

        let margin: CGFloat = 16
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: screenFrame.maxX - panelSize.width - margin,
            y: screenFrame.maxY - panelSize.height - margin
        )
        panel.setFrameOrigin(origin)
    }
}
