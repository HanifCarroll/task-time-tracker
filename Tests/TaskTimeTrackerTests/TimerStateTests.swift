import XCTest
@testable import TaskTimeTracker

final class TimerStateTests: XCTestCase {
    @MainActor
    func testStartInCountdownResetsElapsedWhenAlreadyAtEnd() {
        let state = TimerState()
        state.mode = .countdown
        state.elapsedSeconds = state.countdownSeconds

        state.start()
        defer { state.pause() }

        XCTAssertEqual(state.elapsedSeconds, 0)
        XCTAssertTrue(state.isRunning)
    }

    @MainActor
    func testCountdownDisplayAndProgressReflectElapsedTime() {
        let state = TimerState()
        state.mode = .countdown
        state.countdownSeconds = 120
        state.elapsedSeconds = 30

        XCTAssertEqual(state.displaySeconds, 90)
        XCTAssertEqual(state.progress, 0.25, accuracy: 0.0001)
    }

    @MainActor
    func testTasksCanRunIndependently() {
        let state = TimerState(tasks: [
            TaskTimer(title: "Meetup Tool"),
            TaskTimer(title: "Proposal draft")
        ])
        let firstTaskID = state.tasks[0].id
        let secondTaskID = state.tasks[1].id

        state.startTask(firstTaskID)
        state.startTask(secondTaskID)
        defer {
            state.pauseTask(firstTaskID)
            state.pauseTask(secondTaskID)
        }

        XCTAssertTrue(state.tasks[0].isRunning)
        XCTAssertTrue(state.tasks[1].isRunning)

        state.pauseTask(firstTaskID)

        XCTAssertFalse(state.tasks[0].isRunning)
        XCTAssertTrue(state.tasks[1].isRunning)
        XCTAssertEqual(state.activeTaskCount, 1)
    }

    @MainActor
    func testTaskModesAreIndependent() {
        let state = TimerState(tasks: [
            TaskTimer(title: "Meetup Tool"),
            TaskTimer(title: "Proposal draft")
        ])
        let firstTaskID = state.tasks[0].id
        let secondTaskID = state.tasks[1].id

        state.setMode(for: firstTaskID, .countdown)
        state.setStoppedCountdownMinutes(for: firstTaskID, 10)
        state.startTask(firstTaskID)
        state.startTask(secondTaskID)
        state.setMode(for: firstTaskID, .countUp)
        defer {
            state.pauseTask(firstTaskID)
            state.pauseTask(secondTaskID)
        }

        XCTAssertEqual(state.tasks[0].mode, .countUp)
        XCTAssertEqual(state.tasks[0].elapsedSeconds, 0)
        XCTAssertFalse(state.tasks[0].isRunning)
        XCTAssertEqual(state.tasks[1].mode, .countUp)
        XCTAssertTrue(state.tasks[1].isRunning)
    }

    @MainActor
    func testWorkIntervalsArePersistedOnStartAndPause() throws {
        let store = try makeTemporaryStore()
        let task = TaskTimer(title: "Meetup Tool")
        let state = TimerState(tasks: [task], workLogStore: store)

        state.startTask(task.id)
        state.pauseTask(task.id)

        XCTAssertEqual(try store.intervalCount(), 1)
        XCTAssertEqual(try store.eventCount(type: "timer_started"), 1)
        XCTAssertEqual(try store.eventCount(type: "timer_stopped"), 1)
    }

    @MainActor
    func testDeletingTaskArchivesItForHistory() throws {
        let store = try makeTemporaryStore()
        let task = TaskTimer(title: "Inbox cleanup")
        let state = TimerState(tasks: [task], workLogStore: store)

        state.deleteTask(task.id)

        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertTrue(try store.loadCurrentTasks().isEmpty)
        XCTAssertEqual(try store.eventCount(type: "task_archived"), 1)
    }

    @MainActor
    private func makeTemporaryStore() throws -> WorkLogStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("task-time-tracker-test.sqlite")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return try WorkLogStore(databaseURL: databaseURL)
    }
}
