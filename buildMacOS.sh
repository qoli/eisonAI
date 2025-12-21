#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKSPACE="${WORKSPACE:-$SCRIPT_DIR/eisonAI.xcodeproj/project.xcworkspace}"
SCHEME="${SCHEME:-iOS}"
CONFIGURATION="${CONFIGURATION:-Debug}"
TARGET="${TARGET:-catalyst}" # catalyst | mymac | simulator

default_derived_data="$SCRIPT_DIR/build/DerivedData-$TARGET"
DERIVED_DATA="${DERIVED_DATA:-$default_derived_data}"

pick_my_mac_destination_id() {
  xcrun xcdevice list | python3 -c '
import json, sys
devices = json.load(sys.stdin)

def is_macos_device(d):
    return (d.get("platform") == "com.apple.platform.macosx"
            and not d.get("simulator", False)
            and d.get("available", False))

candidates = [d for d in devices if is_macos_device(d)]
if not candidates:
    sys.exit(1)

for d in candidates:
    if d.get("name") == "My Mac":
        print(d.get("identifier", ""))
        sys.exit(0)

print(candidates[0].get("identifier", ""))
'
}

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

if [[ "$TARGET" == "sim" || "$TARGET" == "simulator" ]]; then
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
  exit 0
fi

if [[ "$TARGET" == "catalyst" || "$TARGET" == "maccatalyst" ]]; then
  DESTINATION="platform=macOS,variant=Mac Catalyst"
  echo "Using My Mac (Mac Catalyst)"

  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build

  APP="$DERIVED_DATA/Build/Products/${CONFIGURATION}-maccatalyst/eisonAI.app"
  if [[ ! -d "$APP" ]]; then
    APP="$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -type d -name '*.app' -path "*-maccatalyst/*" -print -quit 2>/dev/null || true)"
  fi
  if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
    echo "Built .app not found under: $DERIVED_DATA/Build/Products" >&2
    exit 1
  fi

  INFO_PLIST="$APP/Contents/Info.plist"
  if [[ -f "$INFO_PLIST" ]]; then
    BUNDLE_ID="$(
      /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null \
        || plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST"
    )"
    echo "Launching: $BUNDLE_ID"
  else
    echo "Info.plist not found at: $INFO_PLIST" >&2
  fi
  open "$APP"
  exit 0
fi

MY_MAC_ID="${MY_MAC_ID:-}"
if [[ -z "$MY_MAC_ID" ]]; then
  MY_MAC_ID="$(pick_my_mac_destination_id 2>/dev/null || true)"
fi
if [[ -z "$MY_MAC_ID" ]]; then
  echo "Could not determine My Mac destination id. Set MY_MAC_ID=..." >&2
  exit 1
fi

echo "Using My Mac (Designed for iPad): $MY_MAC_ID"

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$MY_MAC_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/eisonAI.app"
if [[ ! -d "$APP" ]]; then
  APP="$(find "$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)"
fi
if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
  echo "Built .app not found under: $DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos" >&2
  exit 1
fi

BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null \
    || plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist"
)"

IPA_DIR="${IPA_DIR:-$SCRIPT_DIR/build/MyMac}"
IPA_PATH="${IPA_PATH:-$IPA_DIR/$(basename "${APP%.app}").ipa}"
mkdir -p "$IPA_DIR"

echo "Packaging IPA (this may take a while)..."
TMPDIR="$(mktemp -d)"
mkdir -p "$TMPDIR/Payload"
rm -f "$IPA_PATH"
cp -R "$APP" "$TMPDIR/Payload/"
( cd "$TMPDIR" && /usr/bin/zip -qry "$IPA_PATH" Payload )
rm -rf "$TMPDIR"

echo "Installing to macOS via iOS App Installer: $IPA_PATH"
PRE_MTIME=0
if [[ -d "/Applications/$(basename "$APP")" ]]; then
  PRE_MTIME="$(stat -f '%m' "/Applications/$(basename "$APP")" 2>/dev/null || echo 0)"
fi
open "$IPA_PATH"

INSTALLED_APP="/Applications/$(basename "$APP")"
for _ in {1..300}; do
  if [[ -d "$INSTALLED_APP" ]]; then
    MTIME="$(stat -f '%m' "$INSTALLED_APP" 2>/dev/null || echo 0)"
    if [[ "$PRE_MTIME" -eq 0 || "$MTIME" -ne "$PRE_MTIME" ]]; then
      break
    fi
  fi
  sleep 1
done

echo "Launching: $BUNDLE_ID"
open -b "$BUNDLE_ID"
