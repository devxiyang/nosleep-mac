#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/NoSleep.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/NoSleep"

case "$MODE" in
  run|--build-only|--debug|--logs|--telemetry|--verify) ;;
  *)
    printf 'Usage: %s [run|--build-only|--debug|--logs|--telemetry|--verify]\n' "$0" >&2
    exit 2
    ;;
esac

if [[ "$MODE" != "--build-only" ]]; then
  app_pattern="$(printf '%s' "$APP_BINARY" | /usr/bin/sed 's/[][\\.^$*+?(){}|]/\\&/g')"
  /usr/bin/pkill -f "^$app_pattern$" >/dev/null 2>&1 || true
fi

if [[ -n "${NOSLEEP_DEVELOPMENT_TEAM:-}" ]]; then
  signing=("DEVELOPMENT_TEAM=$NOSLEEP_DEVELOPMENT_TEAM")
else
  signing=(CODE_SIGNING_ALLOWED=NO)
fi

/usr/bin/xcodebuild \
  -project "$ROOT_DIR/NoSleep.xcodeproj" \
  -scheme NoSleep \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  SYMROOT="$DERIVED_DATA/Build/Products" \
  OBJROOT="$DERIVED_DATA/Build/Intermediates.noindex" \
  "${signing[@]}" \
  build

case "$MODE" in
  --build-only)
    printf '%s\n' "$APP_BUNDLE"
    ;;
  --debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.octoii.nosleep"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    /bin/sleep 1
    /usr/bin/pgrep -f "^$app_pattern$" >/dev/null
    ;;
  run)
    /usr/bin/open -n "$APP_BUNDLE"
    ;;
esac
