import Foundation
@preconcurrency import GRDB

@MainActor
final class WorkLogStore {
    static let applicationSupportFolderName = "Task Time Tracker"
    static let databaseFileName = "task-time-tracker.sqlite"

    private let dbQueue: DatabaseQueue

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(dbQueue)
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA journal_size_limit = 1048576")
        }
    }

    static func makeDefault() throws -> WorkLogStore {
        try WorkLogStore(databaseURL: defaultDatabaseURL())
    }

    static func defaultDatabaseURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let folderURL = applicationSupportURL.appendingPathComponent(
            applicationSupportFolderName,
            isDirectory: true
        )
        return folderURL.appendingPathComponent(databaseFileName, isDirectory: false)
    }

    var databasePath: String {
        dbQueue.path
    }

    func recoverOpenIntervals(at now: Date = Date()) throws {
        let nowMS = Self.timestampMilliseconds(now)
        let fallbackEndMS = try lastHeartbeatMilliseconds() ?? nowMS

        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE work_intervals
                SET ended_at_ms = MAX(started_at_ms, :endedAtMS),
                    end_reason = 'recovered_after_restart'
                WHERE ended_at_ms IS NULL
                """,
                arguments: ["endedAtMS": fallbackEndMS]
            )
            try setMetadata("last_heartbeat_ms", value: String(nowMS), in: db)
        }
    }

    func loadCurrentTasks() throws -> [TaskTimer] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, current_title, current_mode, current_countdown_seconds
                FROM tasks
                WHERE archived_at_ms IS NULL
                ORDER BY display_order ASC, created_at_ms ASC, id ASC
                """
            )

            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                let mode = TimerMode(storageValue: row["current_mode"])
                return TaskTimer(
                    id: id,
                    title: row["current_title"],
                    mode: mode,
                    countdownSeconds: row["current_countdown_seconds"],
                    elapsedSeconds: 0,
                    isRunning: false
                )
            }
        }
    }

    func createTask(_ task: TaskTimer, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try upsertTask(task, at: date, in: db)
            try insertEvent(
                taskID: task.id,
                type: "task_created",
                at: date,
                payload: ["title": task.title],
                in: db
            )
        }
    }

    func updateTaskTitle(taskID: UUID, title: String, at date: Date = Date()) throws {
        let atMS = Self.timestampMilliseconds(date)
        try dbQueue.write { db in
            let currentTitle = try String.fetchOne(
                db,
                sql: "SELECT current_title FROM tasks WHERE id = ?",
                arguments: [taskID.uuidString]
            )
            if let currentTitle, currentTitle == title {
                return
            }

            try db.execute(
                sql: """
                UPDATE tasks
                SET current_title = :title,
                    updated_at_ms = :updatedAtMS
                WHERE id = :id
                """,
                arguments: [
                    "id": taskID.uuidString,
                    "title": title,
                    "updatedAtMS": atMS
                ]
            )
            try insertEvent(
                taskID: taskID,
                type: "task_renamed",
                at: date,
                payload: ["title": title],
                in: db
            )
        }
    }

    func updateTaskMode(_ task: TaskTimer, at date: Date = Date()) throws {
        let atMS = Self.timestampMilliseconds(date)
        try dbQueue.write { db in
            try upsertTask(task, at: date, in: db)
            try db.execute(
                sql: """
                UPDATE tasks
                SET current_mode = :mode,
                    current_countdown_seconds = :countdownSeconds,
                    updated_at_ms = :updatedAtMS
                WHERE id = :id
                """,
                arguments: [
                    "id": task.id.uuidString,
                    "mode": task.mode.storageValue,
                    "countdownSeconds": task.countdownSeconds,
                    "updatedAtMS": atMS
                ]
            )
            try insertEvent(
                taskID: task.id,
                type: "mode_changed",
                at: date,
                payload: [
                    "mode": task.mode.storageValue,
                    "countdownSeconds": task.countdownSeconds
                ],
                in: db
            )
        }
    }

    func updateTaskOrder(_ taskIDs: [UUID], at date: Date = Date()) throws {
        let atMS = Self.timestampMilliseconds(date)
        try dbQueue.write { db in
            for (displayOrder, taskID) in taskIDs.enumerated() {
                try db.execute(
                    sql: """
                    UPDATE tasks
                    SET display_order = :displayOrder,
                        updated_at_ms = :updatedAtMS
                    WHERE id = :id AND archived_at_ms IS NULL
                    """,
                    arguments: [
                        "id": taskID.uuidString,
                        "displayOrder": displayOrder,
                        "updatedAtMS": atMS
                    ]
                )
            }
        }
    }

    func archiveTask(taskID: UUID, at date: Date = Date()) throws {
        let atMS = Self.timestampMilliseconds(date)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE tasks
                SET archived_at_ms = :archivedAtMS,
                    updated_at_ms = :archivedAtMS
                WHERE id = :id
                """,
                arguments: [
                    "id": taskID.uuidString,
                    "archivedAtMS": atMS
                ]
            )
            try insertEvent(
                taskID: taskID,
                type: "task_archived",
                at: date,
                payload: nil,
                in: db
            )
        }
    }

    func startInterval(for task: TaskTimer, at date: Date = Date()) throws -> UUID {
        let intervalID = UUID()
        let startedAtMS = Self.timestampMilliseconds(date)
        let countdownTargetSeconds: Int? = task.mode == .countdown ? task.countdownSeconds : nil

        try dbQueue.write { db in
            try upsertTask(task, at: date, in: db)
            try db.execute(
                sql: """
                INSERT INTO work_intervals (
                    id,
                    task_id,
                    title_snapshot,
                    mode,
                    countdown_target_seconds,
                    started_at_ms,
                    ended_at_ms,
                    end_reason
                ) VALUES (
                    :id,
                    :taskID,
                    :titleSnapshot,
                    :mode,
                    :countdownTargetSeconds,
                    :startedAtMS,
                    NULL,
                    'open'
                )
                """,
                arguments: [
                    "id": intervalID.uuidString,
                    "taskID": task.id.uuidString,
                    "titleSnapshot": displayTitle(for: task),
                    "mode": task.mode.storageValue,
                    "countdownTargetSeconds": countdownTargetSeconds,
                    "startedAtMS": startedAtMS
                ]
            )
            try insertEvent(
                taskID: task.id,
                type: "timer_started",
                at: date,
                payload: [
                    "intervalID": intervalID.uuidString,
                    "mode": task.mode.storageValue
                ],
                in: db
            )
            try setMetadata("last_heartbeat_ms", value: String(startedAtMS), in: db)
        }

        return intervalID
    }

    func endInterval(
        _ intervalID: UUID?,
        taskID: UUID,
        reason: String,
        at date: Date = Date()
    ) throws {
        let endedAtMS = Self.timestampMilliseconds(date)

        try dbQueue.write { db in
            if let intervalID {
                try db.execute(
                    sql: """
                    UPDATE work_intervals
                    SET ended_at_ms = MAX(started_at_ms, :endedAtMS),
                        end_reason = :reason
                    WHERE id = :id
                      AND ended_at_ms IS NULL
                    """,
                    arguments: [
                        "id": intervalID.uuidString,
                        "endedAtMS": endedAtMS,
                        "reason": reason
                    ]
                )
            } else {
                try db.execute(
                    sql: """
                    UPDATE work_intervals
                    SET ended_at_ms = MAX(started_at_ms, :endedAtMS),
                        end_reason = :reason
                    WHERE task_id = :taskID
                      AND ended_at_ms IS NULL
                    """,
                    arguments: [
                        "taskID": taskID.uuidString,
                        "endedAtMS": endedAtMS,
                        "reason": reason
                    ]
                )
            }

            try insertEvent(
                taskID: taskID,
                type: "timer_stopped",
                at: date,
                payload: [
                    "intervalID": intervalID?.uuidString ?? "",
                    "reason": reason
                ],
                in: db
            )
            try setMetadata("last_heartbeat_ms", value: String(endedAtMS), in: db)
        }
    }

    func recordHeartbeat(at date: Date = Date()) throws {
        let atMS = Self.timestampMilliseconds(date)
        try dbQueue.write { db in
            try setMetadata("last_heartbeat_ms", value: String(atMS), in: db)
        }
    }

    func intervalCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM work_intervals") ?? 0
        }
    }

    func eventCount(type: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task_events WHERE event_type = ?",
                arguments: [type]
            ) ?? 0
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createWorkLog") { db in
            try db.execute(sql: """
            CREATE TABLE tasks (
                id TEXT PRIMARY KEY NOT NULL,
                current_title TEXT NOT NULL,
                current_mode TEXT NOT NULL,
                current_countdown_seconds INTEGER NOT NULL,
                created_at_ms INTEGER NOT NULL,
                updated_at_ms INTEGER NOT NULL,
                archived_at_ms INTEGER
            );

            CREATE TABLE work_intervals (
                id TEXT PRIMARY KEY NOT NULL,
                task_id TEXT NOT NULL REFERENCES tasks(id),
                title_snapshot TEXT NOT NULL,
                mode TEXT NOT NULL,
                countdown_target_seconds INTEGER,
                started_at_ms INTEGER NOT NULL,
                ended_at_ms INTEGER,
                end_reason TEXT NOT NULL DEFAULT 'open',
                CHECK (ended_at_ms IS NULL OR ended_at_ms >= started_at_ms)
            );

            CREATE TABLE task_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id TEXT REFERENCES tasks(id),
                event_type TEXT NOT NULL,
                at_ms INTEGER NOT NULL,
                payload_json TEXT
            );

            CREATE TABLE app_metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );

            CREATE INDEX work_intervals_task_id_started_at_ms_idx
                ON work_intervals(task_id, started_at_ms);

            CREATE INDEX work_intervals_started_ended_idx
                ON work_intervals(started_at_ms, ended_at_ms);

            CREATE INDEX task_events_task_id_at_ms_idx
                ON task_events(task_id, at_ms);
            """)
        }
        migrator.registerMigration("addTaskDisplayOrder") { db in
            try db.execute(sql: """
            ALTER TABLE tasks
                ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0;

            WITH ordered_tasks AS (
                SELECT
                    id,
                    ROW_NUMBER() OVER (ORDER BY created_at_ms ASC, id ASC) - 1 AS display_order
                FROM tasks
            )
            UPDATE tasks
            SET display_order = (
                SELECT ordered_tasks.display_order
                FROM ordered_tasks
                WHERE ordered_tasks.id = tasks.id
            );
            """)
        }
        return migrator
    }

    private func lastHeartbeatMilliseconds() throws -> Int64? {
        try dbQueue.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM app_metadata WHERE key = 'last_heartbeat_ms'"
            ) else {
                return nil
            }
            return Int64(value)
        }
    }

    private func upsertTask(_ task: TaskTimer, at date: Date, in db: Database) throws {
        let atMS = Self.timestampMilliseconds(date)
        let displayOrder = try taskDisplayOrder(for: task.id, in: db)
        try db.execute(
            sql: """
            INSERT INTO tasks (
                id,
                current_title,
                current_mode,
                current_countdown_seconds,
                display_order,
                created_at_ms,
                updated_at_ms,
                archived_at_ms
            ) VALUES (
                :id,
                :title,
                :mode,
                :countdownSeconds,
                :displayOrder,
                :createdAtMS,
                :updatedAtMS,
                NULL
            )
            ON CONFLICT(id) DO UPDATE SET
                current_title = excluded.current_title,
                current_mode = excluded.current_mode,
                current_countdown_seconds = excluded.current_countdown_seconds,
                updated_at_ms = excluded.updated_at_ms,
                archived_at_ms = NULL
            """,
            arguments: [
                "id": task.id.uuidString,
                "title": task.title,
                "mode": task.mode.storageValue,
                "countdownSeconds": task.countdownSeconds,
                "displayOrder": displayOrder,
                "createdAtMS": atMS,
                "updatedAtMS": atMS
            ]
        )
    }

    private func taskDisplayOrder(for taskID: UUID, in db: Database) throws -> Int {
        if let displayOrder = try Int.fetchOne(
            db,
            sql: "SELECT display_order FROM tasks WHERE id = ?",
            arguments: [taskID.uuidString]
        ) {
            return displayOrder
        }

        return try Int.fetchOne(
            db,
            sql: """
            SELECT COALESCE(MAX(display_order), -1) + 1
            FROM tasks
            WHERE archived_at_ms IS NULL
            """
        ) ?? 0
    }

    private func insertEvent(
        taskID: UUID?,
        type: String,
        at date: Date,
        payload: [String: Any]?,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO task_events (task_id, event_type, at_ms, payload_json)
            VALUES (:taskID, :eventType, :atMS, :payloadJSON)
            """,
            arguments: [
                "taskID": taskID?.uuidString,
                "eventType": type,
                "atMS": Self.timestampMilliseconds(date),
                "payloadJSON": try Self.payloadJSONString(payload)
            ]
        )
    }

    private func setMetadata(_ key: String, value: String, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO app_metadata (key, value)
            VALUES (:key, :value)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            arguments: [
                "key": key,
                "value": value
            ]
        )
    }

    private static func payloadJSONString(_ payload: [String: Any]?) throws -> String? {
        guard let payload else { return nil }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)
    }

    private static func timestampMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private func displayTitle(for task: TaskTimer) -> String {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled task" : trimmed
    }
}
