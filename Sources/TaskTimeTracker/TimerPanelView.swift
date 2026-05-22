import SwiftUI

struct TimerPanelView: View {
    @ObservedObject var state: TimerState
    let windowController: FloatingTimerWindowController

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

            if state.mode == .countdown {
                Stepper("\(state.countdownMinutes)m", value: $state.countdownMinutes, in: 1...240, step: 5)
                    .labelsHidden()
                    .frame(width: 52)
            }

            Spacer(minLength: 0)
            controls
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Text(state.formattedTime(state.displaySeconds))
                .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())

            if state.mode == .countdown {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 0)
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
