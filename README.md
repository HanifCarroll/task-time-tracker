# Task Time Tracker

A minimalist macOS menu bar timer for keeping track of the tasks you are working on and how much time you have spent on them.

## Features

- Menu bar status item showing active timer state.
- Compact floating SwiftUI timer window with multiple task rows and icon-only controls.
- Window starts at the minimum width and grows only enough to reveal added task rows.
- Optional always-on-top behavior from the menu bar.
- Count-up “Free Time” mode.
- Countdown mode with a configurable duration.
- Independent timer/countdown mode per task.
- SQLite work history for reports and multitasking analysis.
- Row deletion archives tasks without deleting historical intervals.
- Movable and resizable UI window.
- Window opens in the top-right of the screen.
- Show/hide controls from the menu bar.
- One-command local install into `~/Applications` for Spotlight launch.

## Requirements

- macOS 14 or newer
- Xcode / Swift toolchain

## Build

```bash
swift build
```

## Run from source

```bash
swift run TaskTimeTracker
```

## Install or update the app

```bash
./scripts/install-app.sh
```

The script builds a release executable, packages `Task Time Tracker.app`, installs it into `~/Applications`, removes the older `TaskTimeTracker.app` bundle if present, and relaunches the app if it is already running.

## Window sizing

The floating panel starts at its minimum content width. Adding or removing tasks automatically fits the panel height to the visible task rows while keeping the width compact. The window still supports manual resizing, but saved width is normalized back to the compact minimum on restore.

## Work history database

The app stores reportable work history in SQLite:

```text
~/Library/Application Support/Task Time Tracker/task-time-tracker.sqlite
```

The database is optimized for later reporting:

- `tasks` stores current task rows. Deleting a row sets `archived_at_ms`; it does not remove history.
- `work_intervals` stores one row per start/stop interval, with a `title_snapshot`, mode, start time, end time, and stop reason.
- `task_events` stores task lifecycle events such as create, rename, mode change, start, stop, and archive.
- Timestamps are Unix milliseconds in UTC.
- The app writes on state transitions instead of writing every second.

Example report queries:

```sql
-- Total tracked time by task title.
SELECT
  title_snapshot,
  ROUND(SUM(ended_at_ms - started_at_ms) / 60000.0, 1) AS minutes
FROM work_intervals
WHERE ended_at_ms IS NOT NULL
GROUP BY title_snapshot
ORDER BY minutes DESC;

-- Task pairs that overlapped, useful for multitasking reports.
SELECT
  a.title_snapshot AS task_a,
  b.title_snapshot AS task_b,
  COUNT(*) AS overlaps,
  ROUND(SUM(
    MIN(a.ended_at_ms, b.ended_at_ms) -
    MAX(a.started_at_ms, b.started_at_ms)
  ) / 60000.0, 1) AS overlap_minutes
FROM work_intervals a
JOIN work_intervals b
  ON a.id < b.id
 AND a.started_at_ms < b.ended_at_ms
 AND b.started_at_ms < a.ended_at_ms
WHERE a.ended_at_ms IS NOT NULL
  AND b.ended_at_ms IS NOT NULL
GROUP BY task_a, task_b
ORDER BY overlap_minutes DESC;

-- Daily single-task vs multitask signal.
WITH endpoints AS (
  SELECT started_at_ms AS at_ms, 1 AS delta FROM work_intervals WHERE ended_at_ms IS NOT NULL
  UNION ALL
  SELECT ended_at_ms AS at_ms, -1 AS delta FROM work_intervals WHERE ended_at_ms IS NOT NULL
),
points AS (
  SELECT at_ms, SUM(delta) AS delta
  FROM endpoints
  GROUP BY at_ms
),
segments AS (
  SELECT
    at_ms,
    LEAD(at_ms) OVER (ORDER BY at_ms) AS next_ms,
    SUM(delta) OVER (ORDER BY at_ms ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS active_count
  FROM points
)
SELECT
  date(at_ms / 1000, 'unixepoch', 'localtime') AS day,
  ROUND(SUM(CASE WHEN active_count = 1 THEN next_ms - at_ms ELSE 0 END) / 60000.0, 1) AS single_task_minutes,
  ROUND(SUM(CASE WHEN active_count > 1 THEN next_ms - at_ms ELSE 0 END) / 60000.0, 1) AS multitask_minutes
FROM segments
WHERE next_ms IS NOT NULL
GROUP BY day
ORDER BY day DESC;
```

## Development note

After every code or configuration change, run:

```bash
./scripts/install-app.sh
```

This keeps the installed Spotlight app in sync with the working tree.
