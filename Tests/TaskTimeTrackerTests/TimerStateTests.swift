import AppKit
import Combine
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
    func testToggleAllStartsThenPausesEveryTask() {
        let state = TimerState(tasks: [
            TaskTimer(title: "Meetup Tool"),
            TaskTimer(title: "Proposal draft")
        ])

        state.toggleAllRunningTasks()
        XCTAssertTrue(state.tasks.allSatisfy(\.isRunning))

        state.toggleAllRunningTasks()
        XCTAssertTrue(state.tasks.allSatisfy { !$0.isRunning })
    }

    @MainActor
    func testResetAllStopsTimersAndClearsElapsedTime() throws {
        let store = try makeTemporaryStore()
        let state = TimerState(tasks: [
            TaskTimer(title: "Meetup Tool", elapsedSeconds: 42),
            TaskTimer(title: "Proposal draft", elapsedSeconds: 17)
        ], workLogStore: store)

        state.startAllTasks()
        state.resetAllTasks()

        XCTAssertTrue(state.tasks.allSatisfy { !$0.isRunning })
        XCTAssertTrue(state.tasks.allSatisfy { $0.elapsedSeconds == 0 })
        XCTAssertEqual(try store.eventCount(type: "timer_started"), 2)
        XCTAssertEqual(try store.eventCount(type: "timer_stopped"), 2)
    }

    @MainActor
    func testRunningDisplayUsesElapsedWallClockWithoutMutatingStoredElapsedTime() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let task = TaskTimer(
            title: "Meetup Tool",
            elapsedSeconds: 10,
            isRunning: true,
            startedAt: startedAt
        )
        let state = TimerState(tasks: [task])
        defer { state.pauseTask(task.id) }

        XCTAssertEqual(state.displaySeconds(for: task, at: startedAt.addingTimeInterval(7)), 17)
        XCTAssertEqual(state.tasks[0].elapsedSeconds, 10)
    }

    @MainActor
    func testRunningTicksDoNotRepublishTheTaskArray() async throws {
        let task = TaskTimer(title: "Meetup Tool")
        let state = TimerState(tasks: [task])
        var taskArrayPublicationCount = 0
        let cancellable = state.$tasks
            .dropFirst()
            .sink { _ in
                taskArrayPublicationCount += 1
            }

        state.startTask(task.id)
        let publicationCountAfterStart = taskArrayPublicationCount
        try await Task.sleep(for: .seconds(2.2))

        XCTAssertEqual(taskArrayPublicationCount, publicationCountAfterStart)
        state.pauseTask(task.id)
        withExtendedLifetime(cancellable) {}
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
    func testUnchangedTitleDoesNotCreateRenameEvent() throws {
        let store = try makeTemporaryStore()
        let task = TaskTimer(title: "Inbox cleanup")
        let state = TimerState(tasks: [task], workLogStore: store)

        state.setTitle(for: task.id, "Inbox cleanup")
        try store.updateTaskTitle(taskID: task.id, title: "Inbox cleanup")

        XCTAssertEqual(try store.eventCount(type: "task_renamed"), 0)

        state.setTitle(for: task.id, "Inbox review")
        try store.updateTaskTitle(taskID: task.id, title: "Inbox review")

        XCTAssertEqual(state.tasks.first?.title, "Inbox review")
        XCTAssertEqual(try store.eventCount(type: "task_renamed"), 1)
    }

    @MainActor
    func testMovingTaskReordersTasksWithoutChangingSelection() {
        let tasks = [
            TaskTimer(title: "First"),
            TaskTimer(title: "Second"),
            TaskTimer(title: "Third")
        ]
        let state = TimerState(tasks: tasks)
        state.selectTask(tasks[1].id)

        state.moveTask(tasks[2].id, toOffset: 0)

        XCTAssertEqual(state.tasks.map(\.id), [tasks[2].id, tasks[0].id, tasks[1].id])
        XCTAssertEqual(state.selectedTaskID, tasks[1].id)

        state.moveTaskDown(tasks[2].id)
        XCTAssertEqual(state.tasks.map(\.id), [tasks[0].id, tasks[2].id, tasks[1].id])

        state.moveTaskUp(tasks[1].id)
        XCTAssertEqual(state.tasks.map(\.id), [tasks[0].id, tasks[1].id, tasks[2].id])
    }

    @MainActor
    func testMovedTaskOrderPersistsAndNewTasksAppend() throws {
        let store = try makeTemporaryStore()
        let tasks = [
            TaskTimer(title: "First"),
            TaskTimer(title: "Second"),
            TaskTimer(title: "Third")
        ]
        let state = TimerState(tasks: tasks, workLogStore: store)

        state.moveTask(tasks[2].id, toOffset: 0)
        state.addTask()

        XCTAssertEqual(
            try store.loadCurrentTasks().map(\.id),
            [tasks[2].id, tasks[0].id, tasks[1].id, state.tasks.last?.id].compactMap { $0 }
        )
    }

    func testWindowSizingRestoresMinimumWidthAndFitsContentHeight() {
        let restoredSize = FloatingTimerWindowSizing.restoredSize(
            savedWidth: 430,
            savedHeight: 180,
            migrationVersion: 2,
            currentMigrationVersion: 2
        )

        XCTAssertEqual(restoredSize.width, 390)
        XCTAssertEqual(restoredSize.height, 180)
        XCTAssertEqual(FloatingTimerWindowSizing.fittedHeight(for: 70, visibleFrame: nil), 82)

        let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 220)
        XCTAssertEqual(FloatingTimerWindowSizing.fittedHeight(for: 400, visibleFrame: visibleFrame), 156)
        XCTAssertEqual(FloatingTimerWindowSizing.frameHeight(for: 400, visibleFrame: visibleFrame), 188)

        XCTAssertEqual(TimerPanelSizing.contentHeight(for: [TaskTimer(title: "One")]), 82)
        XCTAssertEqual(TimerPanelSizing.contentHeight(for: [
            TaskTimer(title: "One"),
            TaskTimer(title: "Two")
        ]), 107)
        XCTAssertEqual(TimerPanelSizing.contentHeight(for: [
            TaskTimer(title: "One", mode: .countdown),
            TaskTimer(title: "Two")
        ]), 112)
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
