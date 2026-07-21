import SwiftUI

private let taskListCoordinateSpace = "TaskTimeTracker.taskList"

enum TimerPanelSizing {
    static let minimumWidth: CGFloat = 390
    static let minimumHeight: CGFloat = 82
    static let headerHeight: CGFloat = 20
    static let countUpRowHeight: CGFloat = 30
    static let countdownRowHeight: CGFloat = 35
    static let verticalPadding: CGFloat = 17
    static let headerTaskSpacing: CGFloat = 6
    static let taskSpacing: CGFloat = 4

    static func contentHeight(for tasks: [TaskTimer]) -> CGFloat {
        let rowHeights = tasks.reduce(CGFloat.zero) { total, task in
            total + (task.mode == .countdown ? countdownRowHeight : countUpRowHeight)
        }
        let spacingHeight = CGFloat(max(tasks.count - 1, 0)) * taskSpacing
        let contentHeight = verticalPadding + headerHeight + headerTaskSpacing + rowHeights + spacingHeight
        return max(minimumHeight, ceil(contentHeight))
    }
}

struct TimerPanelView: View {
    @ObservedObject var state: TimerState
    let windowController: FloatingTimerWindowController

    @State private var draggedTaskID: TaskTimer.ID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartCenter: CGFloat?
    @State private var taskRowFrames: [TaskTimer.ID: CGRect] = [:]

    var body: some View {
        VStack(spacing: 6) {
            header
            taskList
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(
            minWidth: TimerPanelSizing.minimumWidth,
            idealWidth: TimerPanelSizing.minimumWidth,
            maxWidth: .infinity,
            minHeight: TimerPanelSizing.minimumHeight,
            idealHeight: TimerPanelSizing.minimumHeight,
            maxHeight: .infinity
        )
        .background(.regularMaterial)
        .onChange(of: state.keepOnTop) { _, _ in
            windowController.applyLevel()
        }
        .onDeleteCommand {
            state.deleteSelectedTask()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Task Time Tracker")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(state.taskSummary)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                headerButton(
                    systemName: state.hasRunningTasks ? "pause.fill" : "play.fill",
                    help: state.hasRunningTasks ? "Pause all timers" : "Start all timers",
                    action: state.toggleAllRunningTasks
                )
                .disabled(state.tasks.isEmpty)

                headerButton(
                    systemName: "arrow.counterclockwise",
                    help: "Reset all timers",
                    action: state.resetAllTasks
                )
                .disabled(state.tasks.isEmpty)

                headerButton(
                    systemName: "plus",
                    help: "Add task",
                    action: state.addTask
                )
            }
        }
    }

    private var taskList: some View {
        ScrollView {
            VStack(spacing: TimerPanelSizing.taskSpacing) {
                ForEach($state.tasks) { $task in
                    let isDragging = draggedTaskID == task.id
                    TaskTimerRow(
                        task: $task,
                        isSelected: task.id == state.selectedTaskID,
                        state: state,
                        onReorderDragChanged: { value in
                            updateReorderDrag(for: task.id, value: value)
                        },
                        onReorderDragEnded: { value in
                            finishReorderDrag(for: task.id, value: value)
                        }
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: TaskRowFramePreferenceKey.self,
                                value: [task.id: geometry.frame(in: .named(taskListCoordinateSpace))]
                            )
                        }
                    }
                    .offset(y: isDragging ? dragTranslation : 0)
                    .zIndex(isDragging ? 1 : 0)
                    .shadow(
                        color: .black.opacity(isDragging ? 0.16 : 0),
                        radius: isDragging ? 6 : 0,
                        y: isDragging ? 2 : 0
                    )
                }
            }
        }
        .coordinateSpace(name: taskListCoordinateSpace)
        .onPreferenceChange(TaskRowFramePreferenceKey.self) { taskRowFrames = $0 }
        .scrollIndicators(.hidden)
    }

    private func updateReorderDrag(for taskID: TaskTimer.ID, value: DragGesture.Value) {
        guard draggedTaskID == nil || draggedTaskID == taskID else { return }
        if draggedTaskID == nil {
            draggedTaskID = taskID
            dragStartCenter = taskRowFrames[taskID]?.midY
            state.selectTask(taskID)
        }
        dragTranslation = value.translation.height
    }

    private func finishReorderDrag(for taskID: TaskTimer.ID, value: DragGesture.Value) {
        defer {
            withAnimation(.snappy) {
                draggedTaskID = nil
                dragTranslation = 0
                dragStartCenter = nil
            }
        }

        guard draggedTaskID == taskID,
              let sourceIndex = state.tasks.firstIndex(where: { $0.id == taskID }),
              let dragStartCenter else {
            return
        }

        let draggedCenter = dragStartCenter + value.translation.height
        let destinationIndex = state.tasks
            .filter { $0.id != taskID }
            .compactMap { taskRowFrames[$0.id]?.midY }
            .filter { $0 < draggedCenter }
            .count
        guard destinationIndex != sourceIndex else { return }

        let destinationOffset = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        withAnimation(.snappy) {
            state.moveTask(taskID, toOffset: destinationOffset)
        }
    }

    private func headerButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct TaskTimerRow: View {
    @Binding var task: TaskTimer
    let isSelected: Bool
    @ObservedObject var state: TimerState
    let onReorderDragChanged: (DragGesture.Value) -> Void
    let onReorderDragEnded: (DragGesture.Value) -> Void

    @State private var timeEditorText = ""
    @State private var isHovered = false
    @FocusState private var isTimeEditorFocused: Bool

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                dragHandle

                statusDot

                TaskTitleEditor(task: task, state: state)
                    .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)

                modePicker

                timerDisplay

                controls

                deleteButton
            }

            if task.mode == .countdown {
                countdownProgress
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.045) : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectTask(task.id)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                state.moveTaskUp(task.id)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(!state.canMoveTaskUp(task.id))

            Button {
                state.moveTaskDown(task.id)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(!state.canMoveTaskDown(task.id))

            Divider()

            Button(role: .destructive) {
                state.deleteTask(task.id)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 10, height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(taskListCoordinateSpace))
                    .onChanged(onReorderDragChanged)
                    .onEnded(onReorderDragEnded)
            )
            .help("Drag to reorder")
            .accessibilityLabel("Reorder \(displayTitle)")
            .accessibilityAction(named: "Move up") {
                state.moveTaskUp(task.id)
            }
            .accessibilityAction(named: "Move down") {
                state.moveTaskDown(task.id)
            }
    }

    private var displayTitle: String {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled task" : trimmed
    }

    private var modePicker: some View {
        Picker("Mode", selection: modeBinding) {
            ForEach(TimerMode.allCases) { mode in
                Image(systemName: mode.symbolName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .frame(width: 58)
    }

    private var timerDisplay: some View {
        Group {
            if task.mode == .countdown, !task.isRunning {
                TextField("25", text: $timeEditorText)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($isTimeEditorFocused)
                    .onAppear(perform: syncTimeEditor)
                    .onSubmit(commitTimeEditor)
                    .onChange(of: timeEditorText) { _, newValue in
                        let digitsOnly = newValue.filter(\.isNumber)
                        if digitsOnly != newValue {
                            timeEditorText = digitsOnly
                        }
                    }
                    .onChange(of: isTimeEditorFocused) { _, focused in
                        focused ? syncTimeEditor() : commitTimeEditor()
                    }
                    .onChange(of: task.countdownSeconds) { _, _ in
                        if !isTimeEditorFocused {
                            syncTimeEditor()
                        }
                    }
                    .onChange(of: task.mode) { _, _ in
                        syncTimeEditor()
                    }
                    .onChange(of: task.id) { _, _ in
                        syncTimeEditor()
                    }
            } else if task.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    timerText(at: context.date)
                }
            } else {
                timerText(at: .now)
            }
        }
        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(width: 72, alignment: .trailing)
    }

    private var countdownProgress: some View {
        Group {
            if task.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    progressView(at: context.date)
                }
            } else {
                progressView(at: .now)
            }
        }
        .frame(height: 2)
    }

    private func timerText(at date: Date) -> some View {
        Text(state.formattedTime(state.displaySeconds(for: task, at: date)))
            .contentTransition(.numericText())
    }

    private func progressView(at date: Date) -> some View {
        ProgressView(value: state.progress(for: task, at: date))
            .progressViewStyle(.linear)
            .tint(statusColor)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            fusedControlButton(
                systemName: task.isRunning ? "pause.fill" : "play.fill",
                help: task.isRunning ? "Pause" : "Start",
                action: { state.toggleRunning(for: task.id) }
            )
            Divider()
                .frame(height: 16)
            fusedControlButton(
                systemName: "arrow.counterclockwise",
                help: "Reset",
                action: { state.resetTask(task.id) }
            )
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            state.deleteTask(task.id)
        } label: {
            Image(systemName: "trash")
                .font(.caption.weight(.semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete task")
        .disabled(!(isHovered || isSelected))
        .opacity(isHovered || isSelected ? 1 : 0)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }

    private var statusColor: Color {
        if task.isRunning {
            return Color(nsColor: .systemGreen)
        }

        if task.mode == .countdown {
            return Color(nsColor: .systemYellow)
        }

        return Color.secondary.opacity(0.75)
    }

    private var modeBinding: Binding<TimerMode> {
        Binding(
            get: { task.mode },
            set: { state.setMode(for: task.id, $0) }
        )
    }

    private func syncTimeEditor() {
        timeEditorText = String(max(task.countdownSeconds / 60, 1))
    }

    private func commitTimeEditor() {
        guard let minutes = Int(timeEditorText), minutes > 0 else {
            syncTimeEditor()
            return
        }

        state.setStoppedCountdownMinutes(for: task.id, minutes)
        syncTimeEditor()
    }

    private func fusedControlButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct TaskRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TaskTimer.ID: CGRect] = [:]

    static func reduce(value: inout [TaskTimer.ID: CGRect], nextValue: () -> [TaskTimer.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct TaskTitleEditor: View {
    let task: TaskTimer
    @ObservedObject var state: TimerState

    @State private var draftTitle = ""
    @State private var isEditing = false

    var body: some View {
        Group {
            if isEditing {
                TaskTitleEditField(text: $draftTitle, onCommit: endEditing)
                    .accessibilityLabel("Task")
            } else {
                Text(displayTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(displayTitle)
                    .onTapGesture {
                        state.selectTask(task.id)
                        draftTitle = task.title
                        isEditing = true
                    }
            }
        }
        .font(.caption.weight(.semibold))
    }

    private var displayTitle: String {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled task" : trimmed
    }

    private func endEditing() {
        guard isEditing else { return }
        if draftTitle != task.title {
            state.setTitle(for: task.id, draftTitle)
        }
        isEditing = false
    }
}

private struct TaskTitleEditField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 12, weight: .semibold)
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.textField = textField
        context.coordinator.installOutsideClickMonitors()
        focus(textField)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        context.coordinator.textField = textField
        context.coordinator.installOutsideClickMonitors()

        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.removeOutsideClickMonitors()
    }

    private func focus(_ textField: NSTextField) {
        DispatchQueue.main.async {
            guard textField.currentEditor() == nil else { return }
            textField.window?.makeFirstResponder(textField)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onCommit: () -> Void
        weak var textField: NSTextField?

        private var localMouseDownMonitor: Any?
        private var globalMouseDownMonitor: Any?
        private var isCommitting = false

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        func installOutsideClickMonitors() {
            if localMouseDownMonitor == nil {
                localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    self?.commitIfClickIsOutsideField(event)
                    return event
                }
            }

            if globalMouseDownMonitor == nil {
                globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                    self?.commitCurrentText()
                }
            }
        }

        func removeOutsideClickMonitors() {
            if let localMouseDownMonitor {
                NSEvent.removeMonitor(localMouseDownMonitor)
                self.localMouseDownMonitor = nil
            }

            if let globalMouseDownMonitor {
                NSEvent.removeMonitor(globalMouseDownMonitor)
                self.globalMouseDownMonitor = nil
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                text.wrappedValue = textField.stringValue
            }
            commitCurrentText()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            text.wrappedValue = textView.string
            commitCurrentText()
            return true
        }

        private func commitIfClickIsOutsideField(_ event: NSEvent) {
            guard let textField, event.window === textField.window else { return }

            let locationInField = textField.convert(event.locationInWindow, from: nil)
            guard !textField.bounds.contains(locationInField) else { return }

            commitCurrentText()
        }

        private func commitCurrentText() {
            guard !isCommitting else { return }
            isCommitting = true
            if let textField {
                text.wrappedValue = textField.stringValue
            }
            removeOutsideClickMonitors()
            onCommit()
            isCommitting = false
        }
    }
}
