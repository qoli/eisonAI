#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKSPACE="${WORKSPACE:-$SCRIPT_DIR/eisonAI.xcodeproj/project.xcworkspace}"
SCHEME="${SCHEME:-iOS}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-$SCRIPT_DIR/build/DerivedData}"

pick_booted_simulator() {
  xcrun simctl list devices booted -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("state") == "Booted":
            print(device.get("udid", ""))
            sys.exit(0)
sys.exit(1)
'
}

pick_available_simulator() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
devices_by_runtime = data.get("devices", {})

def runtime_key(runtime_id: str):
    m = re.search(r"iOS-(\d+)-(\d+)$", runtime_id)
    if m:
        return (int(m.group(1)), int(m.group(2)))
    m = re.search(r"iOS-(\d+)$", runtime_id)
    if m:
        return (int(m.group(1)), 0)
    return (0, 0)

runtimes = sorted(devices_by_runtime.keys(), key=runtime_key, reverse=True)

def first_match(pred):
    for rt in runtimes:
        for d in devices_by_runtime.get(rt, []):
            if not d.get("isAvailable", True):
                continue
            if pred(d):
                return d.get("udid")
    return None

udid = first_match(lambda d: "iPhone" in (d.get("name") or "")) or first_match(lambda d: True)
if udid:
    print(udid)
    sys.exit(0)
sys.exit(1)
'
}

SIMULATOR_UDID="${SIMULATOR_UDID:-}"
if [[ -z "$SIMULATOR_UDID" ]]; then
  SIMULATOR_UDID="$(pick_booted_simulator 2>/dev/null || true)"
fi
if [[ -z "$SIMULATOR_UDID" ]]; then
  SIMULATOR_UDID="$(pick_available_simulator)"
fi

echo "Using iOS Simulator: $SIMULATOR_UDID"

xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
open -a Simulator >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/eisonAI.app"
if [[ ! -d "$APP" ]]; then
  APP="$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -type d -name '*.app' -print -quit || true)"
fi
if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
  echo "Built .app not found under: $DERIVED_DATA/Build/Products" >&2
  exit 1
fi

BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null \
    || plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist"
)"

echo "Installing: $APP"
xcrun simctl install "$SIMULATOR_UDID" "$APP"

echo "Launching: $BUNDLE_ID"
xcrun simctl launch --terminate-running-process "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null
