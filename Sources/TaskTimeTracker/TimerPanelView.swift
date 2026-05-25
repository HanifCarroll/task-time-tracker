import SwiftUI

struct TimerPanelView: View {
    @ObservedObject var state: TimerState
    let windowController: FloatingTimerWindowController

    @State private var timeEditorText = ""
    @FocusState private var isTimeEditorFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            taskEditor
            timerDisplay
            bottomBar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(
            minWidth: 220,
            idealWidth: 220,
            maxWidth: .infinity,
            minHeight: 132,
            idealHeight: 132,
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

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: $state.mode) {
                ForEach(TimerMode.allCases) { mode in
                    Image(systemName: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 82)

            Spacer(minLength: 0)
            controls
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Group {
                if state.isRunning {
                    Text(state.formattedTime(state.displaySeconds))
                        .contentTransition(.numericText())
                } else {
                    TextField("00:00", text: $timeEditorText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .focused($isTimeEditorFocused)
                        .onAppear(perform: syncTimeEditor)
                        .onSubmit(commitTimeEditor)
                        .onChange(of: isTimeEditorFocused) { _, focused in
                            focused ? syncTimeEditor() : commitTimeEditor()
                        }
                        .onChange(of: state.displaySeconds) { _, _ in
                            if !isTimeEditorFocused { syncTimeEditor() }
                        }
                        .onChange(of: state.mode) { _, _ in
                            syncTimeEditor()
                        }
                }
            }
            .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity)

            if state.mode == .countdown {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 0)
    }

    private func syncTimeEditor() {
        timeEditorText = state.formattedTime(state.displaySeconds)
    }

    private func commitTimeEditor() {
        guard let seconds = parseTimeEditorText(timeEditorText) else {
            syncTimeEditor()
            return
        }
        state.setStoppedDisplaySeconds(seconds)
        syncTimeEditor()
    }

    private func parseTimeEditorText(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }

        var seconds = 0
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            seconds = seconds * 60 + value
        }
        return seconds
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                state.toggleRunning()
            } label: {
                Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])
            .help(state.isRunning ? "Pause" : "Start")

            Button {
                state.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 16)
            }
            .buttonStyle(.bordered)
            .help("Reset")

            Button {
                state.completeTask()
            } label: {
                Image(systemName: "checkmark")
                    .frame(width: 16)
            }
            .buttonStyle(.bordered)
            .help("Complete task")
        }
    }
}
