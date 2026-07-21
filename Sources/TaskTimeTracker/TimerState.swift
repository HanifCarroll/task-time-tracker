import AppKit
import Combine
import Foundation

enum TimerMode: String, CaseIterable, Identifiable {
    case countUp = "Free Time"
    case countdown = "Countdown"

    var id: String { rawValue }

    var storageValue: String {
        switch self {
        case .countUp: "count_up"
        case .countdown: "countdown"
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case "countdown":
            self = .countdown
        default:
            self = .countUp
        }
    }

    var symbolName: String {
        switch self {
        case .countUp: "stopwatch"
        case .countdown: "timer"
        }
    }
}

struct TaskTimer: Identifiable, Equatable {
    let id: UUID
    var title: String
    var mode: TimerMode
    var countdownSeconds: Int
    var elapsedSeconds: Int
    var isRunning: Bool
    var activeIntervalID: UUID?
    var startedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        mode: TimerMode = .countUp,
        countdownSeconds: Int = 25 * 60,
        elapsedSeconds: Int = 0,
        isRunning: Bool = false,
        activeIntervalID: UUID? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.countdownSeconds = countdownSeconds
        self.elapsedSeconds = elapsedSeconds
        self.isRunning = isRunning
        self.activeIntervalID = activeIntervalID
        self.startedAt = startedAt
    }
}

@MainActor
final class TimerState: ObservableObject {
    @Published var tasks: [TaskTimer]
    @Published private(set) var selectedTaskID: TaskTimer.ID?
    @Published var keepOnTop = true

    let tickPublisher = PassthroughSubject<Date, Never>()

    private let workLogStore: WorkLogStore?
    private var timer: Timer?
    private var lastHeartbeatAt: Date?

    init(tasks: [TaskTimer]? = nil, workLogStore: WorkLogStore? = nil) {
        self.workLogStore = workLogStore

        let initialTasks: [TaskTimer]
        let loadedFromStore: Bool
        if let tasks {
            initialTasks = tasks
            loadedFromStore = false
        } else if let storedTasks = try? workLogStore?.loadCurrentTasks(), !storedTasks.isEmpty {
            initialTasks = storedTasks
            loadedFromStore = true
        } else {
            initialTasks = [TaskTimer(title: "Deep work")]
            loadedFromStore = false
        }

        self.tasks = initialTasks
        self.selectedTaskID = initialTasks.first?.id
        if let tasks, workLogStore != nil {
            for task in tasks {
                persist { try workLogStore?.createTask(task) }
            }
        } else if tasks == nil, !loadedFromStore {
            persist { try workLogStore?.createTask(initialTasks[0]) }
        }
        updateTimerLifecycle()
    }

    var activeTaskCount: Int {
        tasks.filter(\.isRunning).count
    }

    var hasRunningTasks: Bool {
        activeTaskCount > 0
    }

    var statusBarTitle: String {
        let runningTasks = tasks.filter(\.isRunning)
        guard let firstRunningTask = runningTasks.first else {
            return formattedTime(displaySeconds)
        }

        if runningTasks.count == 1 {
            return formattedTime(displaySeconds(for: firstRunningTask))
        }

        return "\(runningTasks.count) active"
    }

    var taskSummary: String {
        "\(tasks.count) \(tasks.count == 1 ? "task" : "tasks"), \(activeTaskCount) running"
    }

    var taskTitle: String {
        get {
            selectedTask?.title ?? ""
        }
        set {
            updateSelectedTask { task in
                task.title = newValue
            }
        }
    }

    var mode: TimerMode {
        get {
            selectedTask?.mode ?? .countUp
        }
        set {
            guard let selectedTaskID else { return }
            setMode(for: selectedTaskID, newValue)
        }
    }

    var countdownSeconds: Int {
        get {
            selectedTask?.countdownSeconds ?? 25 * 60
        }
        set {
            updateSelectedTask { task in
                task.countdownSeconds = max(newValue, 60)
                task.elapsedSeconds = 0
            }
        }
    }

    var elapsedSeconds: Int {
        get {
            selectedTask?.elapsedSeconds ?? 0
        }
        set {
            updateSelectedTask { task in
                task.elapsedSeconds = max(newValue, 0)
            }
        }
    }

    var isRunning: Bool {
        selectedTask?.isRunning ?? false
    }

    var displaySeconds: Int {
        selectedTask.map { displaySeconds(for: $0) } ?? 0
    }

    var progress: Double {
        selectedTask.map { progress(for: $0) } ?? 0
    }

    var currentTaskName: String {
        selectedTask.map(currentTaskName(for:)) ?? "Untitled task"
    }

    var menuBarTitle: String {
        if activeTaskCount > 1 {
            return "\(activeTaskCount) active"
        }

        guard let task = tasks.first(where: \.isRunning) ?? selectedTask else {
            return "No tasks"
        }

        return "\(shortTaskName(for: task)) - \(formattedTime(displaySeconds(for: task)))"
    }

    func addTask() {
        var updatedTasks = tasks
        let task = TaskTimer(title: nextTaskTitle())
        updatedTasks.append(task)
        tasks = updatedTasks
        selectedTaskID = task.id
        persist { try workLogStore?.createTask(task) }
    }

    func selectTask(_ id: TaskTimer.ID) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        selectedTaskID = id
    }

    func moveTask(_ id: TaskTimer.ID, toOffset destinationOffset: Int) {
        guard let sourceIndex = tasks.firstIndex(where: { $0.id == id }) else { return }

        let boundedOffset = min(max(destinationOffset, tasks.startIndex), tasks.endIndex)
        moveTasks(fromOffsets: IndexSet(integer: sourceIndex), toOffset: boundedOffset)
    }

    func moveTasks(fromOffsets sourceOffsets: IndexSet, toOffset destinationOffset: Int) {
        guard !sourceOffsets.isEmpty,
              sourceOffsets.allSatisfy({ tasks.indices.contains($0) }) else { return }

        let boundedOffset = min(max(destinationOffset, tasks.startIndex), tasks.endIndex)
        let movingTasks = sourceOffsets.map { tasks[$0] }
        var updatedTasks = tasks
        for sourceOffset in sourceOffsets.reversed() {
            updatedTasks.remove(at: sourceOffset)
        }

        let removedBeforeDestination = sourceOffsets.lazy.filter { $0 < boundedOffset }.count
        let insertionIndex = boundedOffset - removedBeforeDestination
        updatedTasks.insert(contentsOf: movingTasks, at: insertionIndex)
        guard updatedTasks != tasks else { return }

        tasks = updatedTasks
        persist { try workLogStore?.updateTaskOrder(updatedTasks.map(\.id)) }
    }

    func commitTaskOrder(_ orderedTaskIDs: [TaskTimer.ID]) {
        let currentTaskIDs = tasks.map(\.id)
        guard orderedTaskIDs.count == currentTaskIDs.count,
              Set(orderedTaskIDs) == Set(currentTaskIDs),
              orderedTaskIDs != currentTaskIDs else { return }

        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let updatedTasks = orderedTaskIDs.compactMap { tasksByID[$0] }
        guard updatedTasks.count == tasks.count else { return }

        tasks = updatedTasks
        persist { try workLogStore?.updateTaskOrder(orderedTaskIDs) }
    }

    func moveTaskUp(_ id: TaskTimer.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), index > tasks.startIndex else {
            return
        }
        moveTask(id, toOffset: index - 1)
    }

    func moveTaskDown(_ id: TaskTimer.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), index < tasks.index(before: tasks.endIndex) else {
            return
        }
        moveTask(id, toOffset: index + 2)
    }

    func canMoveTaskUp(_ id: TaskTimer.ID) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        return index > tasks.startIndex
    }

    func canMoveTaskDown(_ id: TaskTimer.ID) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }), !tasks.isEmpty else { return false }
        return index < tasks.index(before: tasks.endIndex)
    }

    func setTitle(for id: TaskTimer.ID, _ title: String) {
        var updatedTasks = tasks
        guard let index = updatedTasks.firstIndex(where: { $0.id == id }) else { return }
        guard updatedTasks[index].title != title else { return }

        updatedTasks[index].title = title
        tasks = updatedTasks
        persist { try workLogStore?.updateTaskTitle(taskID: id, title: title) }
    }

    func setMode(for id: TaskTimer.ID, _ mode: TimerMode) {
        var intervalToClose: UUID?
        var shouldCloseInterval = false
        updateTask(id) { task in
            guard task.mode != mode else { return }
            intervalToClose = task.activeIntervalID
            shouldCloseInterval = task.isRunning
            task.isRunning = false
            task.mode = mode
            task.elapsedSeconds = 0
            task.activeIntervalID = nil
            task.startedAt = nil
            persist { try workLogStore?.updateTaskMode(task) }
        }
        if shouldCloseInterval {
            persist {
                try workLogStore?.endInterval(
                    intervalToClose,
                    taskID: id,
                    reason: "mode_changed"
                )
            }
        }
        updateTimerLifecycle()
    }

    func toggleRunning() {
        guard let selectedTaskID else { return }
        toggleRunning(for: selectedTaskID)
    }

    func toggleRunning(for id: TaskTimer.ID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        task.isRunning ? pauseTask(id) : startTask(id)
    }

    func start() {
        guard let selectedTaskID else { return }
        startTask(selectedTaskID)
    }

    func startTask(_ id: TaskTimer.ID) {
        let now = Date()
        updateTask(id) { task in
            guard !task.isRunning else { return }

            if task.mode == .countdown, task.elapsedSeconds >= task.countdownSeconds {
                task.elapsedSeconds = 0
            }

            task.activeIntervalID = startInterval(for: task)
            task.startedAt = now
            task.isRunning = true
        }
        updateTimerLifecycle()
    }

    func pause() {
        guard let selectedTaskID else { return }
        pauseTask(selectedTaskID)
    }

    func pauseTask(_ id: TaskTimer.ID) {
        let now = Date()
        var intervalToClose: UUID?
        var shouldCloseInterval = false
        updateTask(id) { task in
            intervalToClose = task.activeIntervalID
            shouldCloseInterval = task.isRunning
            task.elapsedSeconds = elapsedSeconds(for: task, at: now)
            task.isRunning = false
            task.activeIntervalID = nil
            task.startedAt = nil
        }
        if shouldCloseInterval {
            persist {
                try workLogStore?.endInterval(
                    intervalToClose,
                    taskID: id,
                    reason: "paused"
                )
            }
        }
        updateTimerLifecycle()
    }

    func reset() {
        guard let selectedTaskID else { return }
        resetTask(selectedTaskID)
    }

    func resetTask(_ id: TaskTimer.ID) {
        var intervalToClose: UUID?
        var shouldCloseInterval = false
        updateTask(id) { task in
            intervalToClose = task.activeIntervalID
            shouldCloseInterval = task.isRunning
            task.isRunning = false
            task.elapsedSeconds = 0
            task.activeIntervalID = nil
            task.startedAt = nil
        }
        if shouldCloseInterval {
            persist {
                try workLogStore?.endInterval(
                    intervalToClose,
                    taskID: id,
                    reason: "reset"
                )
            }
        }
        updateTimerLifecycle()
    }

    func setStoppedCountdownMinutes(_ minutes: Int) {
        guard let selectedTaskID else { return }
        setStoppedCountdownMinutes(for: selectedTaskID, minutes)
    }

    func setStoppedCountdownMinutes(for id: TaskTimer.ID, _ minutes: Int) {
        updateTask(id) { task in
            guard task.mode == .countdown, !task.isRunning else { return }
            task.countdownSeconds = max(minutes, 1) * 60
            task.elapsedSeconds = 0
            task.startedAt = nil
            persist { try workLogStore?.updateTaskMode(task) }
        }
    }

    func deleteTask(_ id: TaskTimer.ID) {
        var intervalToClose: UUID?
        var shouldCloseInterval = false
        var updatedTasks = tasks
        guard let index = updatedTasks.firstIndex(where: { $0.id == id }) else { return }

        intervalToClose = updatedTasks[index].activeIntervalID
        shouldCloseInterval = updatedTasks[index].isRunning
        updatedTasks.remove(at: index)
        tasks = updatedTasks

        if selectedTaskID == id {
            if updatedTasks.indices.contains(index) {
                selectedTaskID = updatedTasks[index].id
            } else {
                selectedTaskID = updatedTasks.last?.id
            }
        }

        if shouldCloseInterval {
            persist {
                try workLogStore?.endInterval(
                    intervalToClose,
                    taskID: id,
                    reason: "deleted"
                )
            }
        }
        persist { try workLogStore?.archiveTask(taskID: id) }
        updateTimerLifecycle()
    }

    func deleteSelectedTask() {
        guard let selectedTaskID else { return }
        deleteTask(selectedTaskID)
    }

    func toggleAllRunningTasks() {
        hasRunningTasks ? pauseAllTasks() : startAllTasks()
    }

    func startAllTasks() {
        let now = Date()
        var updatedTasks = tasks
        var startedAnyTask = false

        for index in updatedTasks.indices where !updatedTasks[index].isRunning {
            if updatedTasks[index].mode == .countdown,
               updatedTasks[index].elapsedSeconds >= updatedTasks[index].countdownSeconds {
                updatedTasks[index].elapsedSeconds = 0
            }

            updatedTasks[index].activeIntervalID = startInterval(for: updatedTasks[index])
            updatedTasks[index].startedAt = now
            updatedTasks[index].isRunning = true
            startedAnyTask = true
        }

        guard startedAnyTask else { return }
        tasks = updatedTasks
        updateTimerLifecycle()
    }

    func pauseAllTasks(reason: String = "paused_all") {
        let now = Date()
        let runningTasks = tasks.filter(\.isRunning)
        guard !runningTasks.isEmpty else { return }

        var updatedTasks = tasks
        for index in updatedTasks.indices where updatedTasks[index].isRunning {
            updatedTasks[index].elapsedSeconds = elapsedSeconds(for: updatedTasks[index], at: now)
            updatedTasks[index].isRunning = false
            updatedTasks[index].activeIntervalID = nil
            updatedTasks[index].startedAt = nil
        }
        tasks = updatedTasks

        for task in runningTasks {
            persist {
                try workLogStore?.endInterval(
                    task.activeIntervalID,
                    taskID: task.id,
                    reason: reason
                )
            }
        }
        updateTimerLifecycle()
    }

    func resetAllTasks() {
        guard !tasks.isEmpty else { return }

        let runningTasks = tasks.filter(\.isRunning)
        tasks = tasks.map { task in
            var updatedTask = task
            updatedTask.elapsedSeconds = 0
            updatedTask.isRunning = false
            updatedTask.activeIntervalID = nil
            updatedTask.startedAt = nil
            return updatedTask
        }

        for task in runningTasks {
            persist {
                try workLogStore?.endInterval(
                    task.activeIntervalID,
                    taskID: task.id,
                    reason: "reset_all"
                )
            }
        }
        updateTimerLifecycle()
    }

    func stopAllRunningTasks(reason: String = "app_quit") {
        pauseAllTasks(reason: reason)
    }

    func displaySeconds(for task: TaskTimer, at date: Date = Date()) -> Int {
        let elapsedSeconds = elapsedSeconds(for: task, at: date)
        return switch task.mode {
        case .countUp:
            elapsedSeconds
        case .countdown:
            max(task.countdownSeconds - elapsedSeconds, 0)
        }
    }

    func progress(for task: TaskTimer, at date: Date = Date()) -> Double {
        guard task.mode == .countdown else { return 0 }
        let total = max(task.countdownSeconds, 1)
        return min(Double(elapsedSeconds(for: task, at: date)) / Double(total), 1)
    }

    func currentTaskName(for task: TaskTimer) -> String {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled task" : trimmed
    }

    func formattedTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private var selectedTask: TaskTimer? {
        guard let selectedIndex else { return nil }
        return tasks[selectedIndex]
    }

    private var selectedIndex: Int? {
        if let selectedTaskID, let index = tasks.firstIndex(where: { $0.id == selectedTaskID }) {
            return index
        }

        return tasks.indices.first
    }

    private func updateSelectedTask(_ changes: (inout TaskTimer) -> Void) {
        guard let selectedTaskID else { return }
        updateTask(selectedTaskID, changes)
    }

    private func updateTask(_ id: TaskTimer.ID, _ changes: (inout TaskTimer) -> Void) {
        var updatedTasks = tasks
        guard let index = updatedTasks.firstIndex(where: { $0.id == id }) else { return }
        changes(&updatedTasks[index])
        tasks = updatedTasks
    }

    private func updateTimerLifecycle() {
        if hasRunningTasks {
            ensureTimer()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func ensureTimer() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 0.1
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let now = Date()
        var updatedTasks = tasks
        var shouldBeep = false
        var completedIntervals: [(intervalID: UUID?, taskID: UUID)] = []

        for index in updatedTasks.indices where updatedTasks[index].isRunning {
            if updatedTasks[index].mode == .countdown,
               elapsedSeconds(for: updatedTasks[index], at: now) >= updatedTasks[index].countdownSeconds {
                updatedTasks[index].elapsedSeconds = updatedTasks[index].countdownSeconds
                updatedTasks[index].isRunning = false
                completedIntervals.append((
                    intervalID: updatedTasks[index].activeIntervalID,
                    taskID: updatedTasks[index].id
                ))
                updatedTasks[index].activeIntervalID = nil
                updatedTasks[index].startedAt = nil
                shouldBeep = true
            }
        }

        if !completedIntervals.isEmpty {
            tasks = updatedTasks
        }
        for completedInterval in completedIntervals {
            persist {
                try workLogStore?.endInterval(
                    completedInterval.intervalID,
                    taskID: completedInterval.taskID,
                    reason: "countdown_completed"
                )
            }
        }

        if shouldBeep {
            NSSound.beep()
        }

        tickPublisher.send(now)
        recordHeartbeatIfNeeded()
        updateTimerLifecycle()
    }

    private func elapsedSeconds(for task: TaskTimer, at date: Date) -> Int {
        guard task.isRunning, let startedAt = task.startedAt else {
            return task.elapsedSeconds
        }

        return task.elapsedSeconds + max(Int(date.timeIntervalSince(startedAt)), 0)
    }

    private func startInterval(for task: TaskTimer) -> UUID? {
        do {
            return try workLogStore?.startInterval(for: task)
        } catch {
            reportPersistenceError(error)
            return nil
        }
    }

    private func persist(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            reportPersistenceError(error)
        }
    }

    private func reportPersistenceError(_ error: Error) {
        fputs("Task Time Tracker persistence error: \(error)\n", stderr)
    }

    private func recordHeartbeatIfNeeded() {
        guard hasRunningTasks else { return }

        let now = Date()
        if let lastHeartbeatAt, now.timeIntervalSince(lastHeartbeatAt) < 60 {
            return
        }

        lastHeartbeatAt = now
        persist { try workLogStore?.recordHeartbeat(at: now) }
    }

    private func shortTaskName(for task: TaskTimer) -> String {
        let name = currentTaskName(for: task)
        guard name.count > 18 else { return name }
        return "\(name.prefix(15))..."
    }

    private func nextTaskTitle() -> String {
        let baseTitle = "New task"
        let existingTitles = Set(tasks.map(\.title))
        guard existingTitles.contains(baseTitle) else { return baseTitle }

        var suffix = 2
        while existingTitles.contains("\(baseTitle) \(suffix)") {
            suffix += 1
        }
        return "\(baseTitle) \(suffix)"
    }
}
