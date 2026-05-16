#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
EXECUTABLE_NAME="MeridianBrowser"
PRODUCT_NAME="Meridian Browser"
BUNDLE_ID="app.meridianbrowser.MeridianBrowser"
MIN_SYSTEM_VERSION="26.0"
SWIFT_CONFIGURATION="debug"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$PRODUCT_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

case "$MODE" in
  --release|release|--verify-release|verify-release|--profile-swiftui|profile-swiftui|--profile-hitches|profile-hitches|--profile-time|profile-time)
    SWIFT_CONFIGURATION="release"
    ;;
esac

pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true

swift build -c "$SWIFT_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$SWIFT_CONFIGURATION" --show-bin-path)/$EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

profile_app() {
  local template="$1"
  local output_name="$2"
  local time_limit="${3:-20s}"
  local output_path="$DIST_DIR/$output_name"

  rm -rf "$output_path"
  open_app
  sleep 1

  local pid
  pid="$(pgrep -x "$EXECUTABLE_NAME" | head -n 1)"
  if [[ -z "$pid" ]]; then
    echo "error: $EXECUTABLE_NAME is not running" >&2
    exit 1
  fi

  echo "Recording $template for $time_limit. Reproduce the sidebar swipe now."
  xcrun xctrace record \
    --template "$template" \
    --attach "$pid" \
    --time-limit "$time_limit" \
    --output "$output_path" \
    --no-prompt
  echo "Trace written to $output_path"
}

case "$MODE" in
  run)
    open_app
    ;;
  --release|release)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --subsystem-logs|subsystem-logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --telemetry|telemetry)
    echo "warning: --telemetry is deprecated; use --subsystem-logs for local developer diagnostics" >&2
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    ;;
  --verify-release|verify-release)
    open_app
    sleep 1
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    ;;
  --profile-swiftui|profile-swiftui)
    profile_app "SwiftUI" "sidebar-swiftui.trace" "20s"
    ;;
  --profile-hitches|profile-hitches)
    profile_app "Animation Hitches" "sidebar-hitches.trace" "20s"
    ;;
  --profile-time|profile-time)
    profile_app "Time Profiler" "sidebar-time-profiler.trace" "20s"
    ;;
  *)
    echo "usage: $0 [run|--release|--debug|--logs|--subsystem-logs|--verify|--verify-release|--profile-swiftui|--profile-hitches|--profile-time]" >&2
    exit 2
    ;;
esac
