import SwiftUI

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

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add task")
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
        }
    }

    private var taskList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach($state.tasks) { $task in
                    TaskTimerRow(
                        task: $task,
                        isSelected: task.id == state.selectedTaskID,
                        state: state
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func addTask() {
        state.addTask()
        windowController.scheduleFitHeightToTasks()
    }
}

private struct TaskTimerRow: View {
    @Binding var task: TaskTimer
    let isSelected: Bool
    @ObservedObject var state: TimerState

    @State private var timeEditorText = ""
    @State private var isHovered = false
    @FocusState private var isTimeEditorFocused: Bool

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                statusDot

                TaskTitleEditor(task: task, state: state)
                    .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)

                modePicker

                timerDisplay

                controls

                deleteButton
            }

            if task.mode == .countdown {
                ProgressView(value: state.progress(for: task))
                    .progressViewStyle(.linear)
                    .tint(statusColor)
                    .frame(height: 2)
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
            Button(role: .destructive) {
                state.deleteTask(task.id)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
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
            } else {
                Text(state.formattedTime(state.displaySeconds(for: task)))
                    .contentTransition(.numericText())
            }
        }
        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(width: 72, alignment: .trailing)
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

private struct TaskTitleEditor: View {
    let task: TaskTimer
    @ObservedObject var state: TimerState

    @State private var draftTitle = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("Task", text: $draftTitle)
                    .accessibilityLabel("Task")
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(endEditing)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            endEditing()
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            isFocused = true
                        }
                    }
            } else {
                Text(displayTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .help("Edit task name")
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
        isFocused = false
        isEditing = false
    }
}
