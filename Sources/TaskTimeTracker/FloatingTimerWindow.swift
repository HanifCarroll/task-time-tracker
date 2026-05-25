import AppKit
import SwiftUI

@MainActor
final class FloatingTimerWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false

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

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 132),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Task Time Tracker"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 220, height: 132)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: TimerPanelView(state: state, windowController: self))
        positionInTopRight(panel)
        return panel
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
