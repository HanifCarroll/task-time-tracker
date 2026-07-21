#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TaskTimeTracker"
APP_DISPLAY_NAME="Task Time Tracker"
BUNDLE_NAME="$APP_DISPLAY_NAME.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="release"
EXECUTABLE_PATH="$REPO_ROOT/.build/$BUILD_CONFIG/$APP_NAME"
APP_DIR="${TASK_TIME_TRACKER_APP_DIR:-$HOME/Applications}"
BUNDLE_PATH="$APP_DIR/$BUNDLE_NAME"
LEGACY_BUNDLE_PATH="$APP_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$REPO_ROOT/Resources/TaskTimeTracker.icns"
WAS_RUNNING=0

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
	WAS_RUNNING=1
fi

cd "$REPO_ROOT"
swift build -c "$BUILD_CONFIG"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$ICON_SOURCE" "$RESOURCES_DIR/$APP_NAME.icns"

if [[ "$LEGACY_BUNDLE_PATH" != "$BUNDLE_PATH" && -d "$LEGACY_BUNDLE_PATH" ]]; then
	rm -rf "$LEGACY_BUNDLE_PATH"
fi

cat >"$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.hanifcarroll.task-time-tracker</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat >"$CONTENTS_DIR/PkgInfo" <<PKGINFO
APPL????
PKGINFO

/usr/bin/codesign --force --sign - "$BUNDLE_PATH"
/usr/bin/mdimport "$BUNDLE_PATH" >/dev/null 2>&1 || true

if ((WAS_RUNNING)); then
	pkill -x "$APP_NAME" || true
	sleep 0.5
	open "$BUNDLE_PATH"
fi

printf 'Installed %s\n' "$BUNDLE_PATH"
if ((WAS_RUNNING)); then
	printf 'Updated running app and relaunched it.\n'
else
	printf 'Run with: open %q\n' "$BUNDLE_PATH"
fi
