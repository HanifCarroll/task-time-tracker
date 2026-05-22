import SwiftUI

struct TimerPanelView: View {
    @ObservedObject var state: TimerState
    let windowController: FloatingTimerWindowController

    var body: some View {
        VStack(spacing: 8) {
            taskEditor
            timerDisplay
            modePicker
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(
            minWidth: 220,
            idealWidth: 220,
            maxWidth: .infinity,
            minHeight: 175,
            idealHeight: 175,
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
            .font(.title3.weight(.medium))
            .multilineTextAlignment(.center)
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            Picker("Mode", selection: $state.mode) {
                ForEach(TimerMode.allCases) { mode in
                    Image(systemName: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if state.mode == .countdown {
                Stepper("\(state.countdownMinutes)m", value: $state.countdownMinutes, in: 1...240, step: 5)
                    .labelsHidden()
                    .frame(width: 70)
            }

            Toggle("Float", isOn: $state.keepOnTop)
                .labelsHidden()
                .toggleStyle(.switch)
                .help("Keep window above other apps")
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Text(state.formattedTime(state.displaySeconds))
                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())

            if state.mode == .countdown {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 2)
    }

    private var controls: some View {
        HStack(spacing: 10) {
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

            Button("Done") {
                state.completeTask()
            }
            .buttonStyle(.bordered)
        }
    }
}
