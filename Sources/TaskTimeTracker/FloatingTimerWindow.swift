import AppKit
import Combine
import SwiftUI

enum FloatingTimerWindowSizing {
    static let minimumSize = NSSize(width: 390, height: 82)
    static let legacyDefaultSize = NSSize(width: 220, height: 132)
    static let oversizedDefaultSize = NSSize(width: 620, height: 300)
    static let visibleFrameMargin: CGFloat = 16
    static let frameHeightAllowance: CGFloat = 32

    static func restoredSize(
        savedWidth: Double,
        savedHeight: Double,
        migrationVersion: Int,
        currentMigrationVersion: Int
    ) -> NSSize {
        guard migrationVersion >= currentMigrationVersion,
              savedWidth >= minimumSize.width,
              savedHeight >= minimumSize.height,
              savedWidth != legacyDefaultSize.width,
              savedHeight != legacyDefaultSize.height,
              savedWidth < oversizedDefaultSize.width,
              savedHeight < oversizedDefaultSize.height
        else {
            return minimumSize
        }

        return NSSize(width: minimumSize.width, height: max(minimumSize.height, savedHeight))
    }

    static func fittedHeight(
        for contentHeight: CGFloat,
        visibleFrame: NSRect?,
        frameHeightAllowance: CGFloat = Self.frameHeightAllowance
    ) -> CGFloat {
        let targetHeight = max(minimumSize.height, ceil(contentHeight))
        guard let visibleFrame else { return targetHeight }

        let maximumHeight = max(minimumSize.height, visibleFrame.height - (visibleFrameMargin * 2) - frameHeightAllowance)
        return min(targetHeight, maximumHeight)
    }

    static func frameHeight(
        for contentHeight: CGFloat,
        visibleFrame: NSRect?,
        frameHeightAllowance: CGFloat = Self.frameHeightAllowance
    ) -> CGFloat {
        fittedHeight(
            for: contentHeight,
            visibleFrame: visibleFrame,
            frameHeightAllowance: frameHeightAllowance
        ) + frameHeightAllowance
    }
}

@MainActor
final class FloatingTimerWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false

    private static let savedWidthKey = "FloatingTimerWindow.width"
    private static let savedHeightKey = "FloatingTimerWindow.height"
    private static let savedSizeMigrationKey = "FloatingTimerWindow.compactSizeMigration"
    private static let compactSizeMigrationVersion = 2

    private let state: TimerState
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(state: TimerState) {
        self.state = state
        super.init()
        Self.migrateSavedSizeIfNeeded()
        bindStateSizing()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        applyLevel()
        fitHeightToTasks(state.tasks)
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

    func fitHeightToContent(_ contentHeight: CGFloat) {
        guard contentHeight > 0, let panel else { return }

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let frameHeightAllowance = max(
            FloatingTimerWindowSizing.frameHeightAllowance,
            panel.frame.height - panel.contentLayoutRect.height
        )
        let targetContentHeight = FloatingTimerWindowSizing.fittedHeight(
            for: contentHeight,
            visibleFrame: visibleFrame,
            frameHeightAllowance: frameHeightAllowance
        )
        let targetFrameHeight = FloatingTimerWindowSizing.frameHeight(
            for: contentHeight,
            visibleFrame: visibleFrame,
            frameHeightAllowance: frameHeightAllowance
        )
        let targetFrameWidth = max(panel.frame.width, FloatingTimerWindowSizing.minimumSize.width)
        let targetContentSize = NSSize(width: FloatingTimerWindowSizing.minimumSize.width, height: targetContentHeight)

        let topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        let targetFrame = NSRect(
            x: topRight.x - targetFrameWidth,
            y: topRight.y - targetFrameHeight,
            width: targetFrameWidth,
            height: targetFrameHeight
        )
        let frameChanged = abs(panel.frame.width - targetFrame.width) > 0.5
            || abs(panel.frame.height - targetFrame.height) > 0.5
        guard frameChanged else { return }

        panel.setFrame(targetFrame, display: panel.isVisible, animate: false)
        saveSize(targetContentSize)
    }

    func scheduleFitHeightToTasks() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fitHeightToTasks(self.state.tasks)
        }
    }

    private func fitHeightToTasks(_ tasks: [TaskTimer]) {
        fitHeightToContent(TimerPanelSizing.contentHeight(for: tasks))
    }

    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        saveSize(panel.contentRect(forFrameRect: panel.frame).size)
    }

    func makePanel() -> NSPanel {
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
        // Keep content drags available to controls such as the task reorder grip.
        // The standard title bar remains the dedicated window-drag region.
        panel.isMovableByWindowBackground = false
        panel.contentMinSize = FloatingTimerWindowSizing.minimumSize
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: TimerPanelView(state: state, windowController: self))
        positionInTopRight(panel)
        return panel
    }

    private func savedSize() -> NSSize {
        let defaults = UserDefaults.standard
        let size = FloatingTimerWindowSizing.restoredSize(
            savedWidth: defaults.double(forKey: Self.savedWidthKey),
            savedHeight: defaults.double(forKey: Self.savedHeightKey),
            migrationVersion: defaults.integer(forKey: Self.savedSizeMigrationKey),
            currentMigrationVersion: Self.compactSizeMigrationVersion
        )
        Self.saveSize(size, in: defaults)
        return size
    }

    private func saveSize(_ size: NSSize) {
        Self.saveSize(size, in: .standard)
    }

    private func bindStateSizing() {
        state.$tasks
            .map { TimerPanelSizing.contentHeight(for: $0) }
            .removeDuplicates()
            .sink { [weak self] contentHeight in
                DispatchQueue.main.async {
                    self?.fitHeightToContent(contentHeight)
                }
            }
            .store(in: &cancellables)
    }

    private static func migrateSavedSizeIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: savedSizeMigrationKey) < compactSizeMigrationVersion else { return }
        saveSize(FloatingTimerWindowSizing.minimumSize, in: defaults)
    }

    private static func saveSize(_ size: NSSize, in defaults: UserDefaults) {
        defaults.set(FloatingTimerWindowSizing.minimumSize.width, forKey: savedWidthKey)
        defaults.set(max(FloatingTimerWindowSizing.minimumSize.height, size.height), forKey: savedHeightKey)
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
