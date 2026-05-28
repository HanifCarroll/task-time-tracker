import SwiftUI

struct TimerPanelView: View {
    @ObservedObject var state: TimerState
    let windowController: FloatingTimerWindowController

    @State private var timeEditorText = ""
    @FocusState private var isTimeEditorFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            taskEditor
            mainRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(
            minWidth: 320,
            idealWidth: 320,
            maxWidth: .infinity,
            minHeight: 104,
            idealHeight: 104,
            maxHeight: .infinity
        )
        .background(.regularMaterial)
        .onChange(of: state.keepOnTop) { _, _ in
            windowController.applyLevel()
        }
    }

    private var taskEditor: some View {
        TextField("Task", text: $state.taskTitle)
            .textFieldStyle(.plain)
            .font(.callout.weight(.medium))
            .multilineTextAlignment(.center)
    }

    private var mainRow: some View {
        HStack(alignment: .center, spacing: 8) {
            modePicker
            timerDisplay
            controls
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $state.mode) {
            ForEach(TimerMode.allCases) { mode in
                Image(systemName: mode.symbolName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 82)
    }

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Group {
                if state.mode == .countdown, !state.isRunning {
                    TextField("25", text: $timeEditorText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .focused($isTimeEditorFocused)
                        .onAppear(perform: syncTimeEditor)
                        .onSubmit(commitTimeEditor)
                        .onChange(of: timeEditorText) { _, newValue in
                            let digitsOnly = newValue.filter(\.isNumber)
                            if digitsOnly != newValue { timeEditorText = digitsOnly }
                        }
                        .onChange(of: isTimeEditorFocused) { _, focused in
                            focused ? syncTimeEditor() : commitTimeEditor()
                        }
                        .onChange(of: state.displaySeconds) { _, _ in
                            if !isTimeEditorFocused { syncTimeEditor() }
                        }
                        .onChange(of: state.mode) { _, _ in
                            syncTimeEditor()
                        }
                } else {
                    Text(state.formattedTime(state.displaySeconds))
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)

            if state.mode == .countdown {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func syncTimeEditor() {
        timeEditorText = String(max(state.countdownSeconds / 60, 1))
    }

    private func commitTimeEditor() {
        guard let minutes = Int(timeEditorText), minutes > 0 else {
            syncTimeEditor()
            return
        }
        state.setStoppedCountdownMinutes(minutes)
        syncTimeEditor()
    }

    private var controls: some View {
        HStack(spacing: 0) {
            fusedControlButton(
                systemName: state.isRunning ? "pause.fill" : "play.fill",
                help: state.isRunning ? "Pause" : "Start",
                usesSpaceShortcut: true,
                action: state.toggleRunning
            )
            Divider()
                .frame(height: 18)
            fusedControlButton(
                systemName: "arrow.counterclockwise",
                help: "Reset",
                action: state.reset
            )
            Divider()
                .frame(height: 18)
            fusedControlButton(
                systemName: "checkmark",
                help: "Complete task",
                action: state.completeTask
            )
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func fusedControlButton(
        systemName: String,
        help: String,
        usesSpaceShortcut: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)

        if usesSpaceShortcut {
            button.keyboardShortcut(.space, modifiers: [])
        } else {
            button
        }
    }
}
