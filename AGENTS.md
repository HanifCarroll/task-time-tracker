# Task Time Tracker Agent Instructions

## After every change

Run the install/update script after every code or configuration change so the installed Spotlight app matches the working tree and any running app is relaunched:

```bash
./scripts/install-app.sh
```

This script builds the release executable, installs `TaskTimeTracker.app` into `~/Applications`, and restarts the app if it is already running.
