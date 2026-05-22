# Task Time Tracker

A minimalist macOS menu bar timer for keeping track of the task you are working on and how much time you have spent on it.

## Features

- Menu bar status item showing the current task and timer.
- Floating SwiftUI timer window that can stay above other apps.
- Count-up “Free Time” mode.
- Countdown mode with a configurable duration.
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

The script builds a release executable, packages `TaskTimeTracker.app`, installs it into `~/Applications`, and relaunches the app if it is already running.

## Development note

After every code or configuration change, run:

```bash
./scripts/install-app.sh
```

This keeps the installed Spotlight app in sync with the working tree.
