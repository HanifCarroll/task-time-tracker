import AppKit
import SwiftUI

@MainActor
final class FloatingTimerWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false

    private static let legacyDefaultSize = NSSize(width: 220, height: 132)
    private static let oversizedDefaultSize = NSSize(width: 620, height: 300)
    private static let defaultSize = NSSize(width: 430, height: 96)
    private static let savedWidthKey = "FloatingTimerWindow.width"
    private static let savedHeightKey = "FloatingTimerWindow.height"
    private static let savedSizeMigrationKey = "FloatingTimerWindow.compactSizeMigration"
    private static let compactSizeMigrationVersion = 1

    private let state: TimerState
    private var panel: NSPanel?

    init(state: TimerState) {
        self.state = state
        super.init()
        Self.migrateSavedSizeIfNeeded()
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
        if Self.shouldMigrateSavedSize(width: width, height: height) {
            Self.saveSize(Self.defaultSize, in: defaults)
            return Self.defaultSize
        }

        guard width >= Self.defaultSize.width, height >= Self.defaultSize.height else {
            defaults.set(Self.compactSizeMigrationVersion, forKey: Self.savedSizeMigrationKey)
            return Self.defaultSize
        }

        if (width == Self.legacyDefaultSize.width && height == Self.legacyDefaultSize.height)
            || (width >= Self.oversizedDefaultSize.width && height >= Self.oversizedDefaultSize.height) {
            Self.saveSize(Self.defaultSize, in: defaults)
            defaults.set(Self.compactSizeMigrationVersion, forKey: Self.savedSizeMigrationKey)
            return Self.defaultSize
        }

        defaults.set(Self.compactSizeMigrationVersion, forKey: Self.savedSizeMigrationKey)
        return NSSize(width: width, height: height)
    }

    private func saveSize(_ size: NSSize) {
        Self.saveSize(size, in: .standard)
    }

    private static func migrateSavedSizeIfNeeded() {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: savedWidthKey)
        let height = defaults.double(forKey: savedHeightKey)

        guard shouldMigrateSavedSize(width: width, height: height) else { return }
        saveSize(defaultSize, in: defaults)
    }

    private static func shouldMigrateSavedSize(width: Double, height: Double) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: savedSizeMigrationKey) < compactSizeMigrationVersion else {
            return false
        }

        return width > defaultSize.width || height > defaultSize.height
    }

    private static func saveSize(_ size: NSSize, in defaults: UserDefaults) {
        defaults.set(size.width, forKey: savedWidthKey)
        defaults.set(size.height, forKey: savedHeightKey)
        defaults.set(compactSizeMigrationVersion, forKey: savedSizeMigrationKey)
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
