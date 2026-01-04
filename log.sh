#!/usr/bin/env bash
set -euo pipefail

SUBSYSTEM="${SUBSYSTEM:-com.qoli.eisonAI}"
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_STYLE="${LOG_STYLE:-compact}"
DEFAULT_PREDICATE="subsystem == \"${SUBSYSTEM}\""
LOG_PREDICATE="${LOG_PREDICATE:-$DEFAULT_PREDICATE}"
LOG_LAST="${LOG_LAST:-15m}"

SOURCE_KIND="${SOURCE_KIND:-}"
SOURCE_UDID="${SOURCE_UDID:-}"

usage() {
  cat <<'EOF'
Usage: ./log.sh [options]

Options:
  --source local|simulator|device   Select log source kind
  --udid <udid>                     Specify device/simulator UDID
  --predicate <predicate>           NSPredicate filter (quote if it has spaces)
  --level info|debug                Log level for streaming
  --style compact|syslog|json        Output style for streaming/show
  --last <duration>                 Device log window (e.g., 5m, 1h)
  --list                            Print available sources and exit
  -h, --help                        Show help

Notes:
  - simulator uses: xcrun simctl spawn <udid> log stream ...
  - device uses: log collect --device-udid <udid> (not live streaming)
EOF
}

list_physical_devices() {
  if ! command -v xcrun >/dev/null 2>&1; then
    return 0
  fi
  xcrun xcdevice list | python3 - <<'PY'
import json, sys
try:
    devices = json.load(sys.stdin)
except Exception:
    sys.exit(0)

for d in devices:
    if d.get("simulator", False):
        continue
    if not d.get("available", False):
        continue
    platform = d.get("platform", "")
    if not platform.startswith("com.apple.platform.ios"):
        continue
    name = d.get("name") or "Device"
    udid = d.get("identifier") or ""
    if udid:
        print(f"{name}|{udid}")
PY
}

list_booted_simulators() {
  if ! command -v xcrun >/dev/null 2>&1; then
    return 0
  fi
  xcrun simctl list devices booted -j | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

for devices in data.get("devices", {}).values():
    for d in devices:
        if d.get("state") != "Booted":
            continue
        name = d.get("name") or "Simulator"
        udid = d.get("udid") or ""
        if udid:
            print(f"{name}|{udid}")
PY
}

list_sources() {
  echo "local|Local Mac"
  while IFS='|' read -r name udid; do
    echo "simulator|${name}|${udid}"
  done < <(list_booted_simulators)
  while IFS='|' read -r name udid; do
    echo "device|${name}|${udid}"
  done < <(list_physical_devices)
}

choose_source() {
  local options=()
  local kinds=()
  local udids=()

  options+=("Local Mac")
  kinds+=("local")
  udids+=("")

  while IFS='|' read -r name udid; do
    options+=("iOS Simulator - ${name} (${udid})")
    kinds+=("simulator")
    udids+=("$udid")
  done < <(list_booted_simulators)

  while IFS='|' read -r name udid; do
    options+=("Device - ${name} (${udid})")
    kinds+=("device")
    udids+=("$udid")
  done < <(list_physical_devices)

  if [[ ${#options[@]} -eq 1 ]]; then
    SOURCE_KIND="local"
    SOURCE_UDID=""
    return
  fi

  echo "Select log source:"
  PS3="> "
  select opt in "${options[@]}"; do
    if [[ -n "${opt:-}" ]]; then
      local idx=$((REPLY - 1))
      SOURCE_KIND="${kinds[$idx]}"
      SOURCE_UDID="${udids[$idx]}"
      break
    fi
    echo "Invalid selection."
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_KIND="${2:-}"
      shift 2
      ;;
    --udid)
      SOURCE_UDID="${2:-}"
      shift 2
      ;;
    --predicate)
      LOG_PREDICATE="${2:-}"
      shift 2
      ;;
    --level)
      LOG_LEVEL="${2:-}"
      shift 2
      ;;
    --style)
      LOG_STYLE="${2:-}"
      shift 2
      ;;
    --last)
      LOG_LAST="${2:-}"
      shift 2
      ;;
    --list)
      list_sources
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SOURCE_KIND" ]]; then
  choose_source
fi

if [[ -z "$SOURCE_KIND" ]]; then
  echo "No log source selected." >&2
  exit 1
fi

case "$SOURCE_KIND" in
  local)
    exec /usr/bin/log stream --style "$LOG_STYLE" --level "$LOG_LEVEL" --predicate "$LOG_PREDICATE"
    ;;
  simulator)
    if [[ -z "$SOURCE_UDID" ]]; then
      SOURCE_UDID="$(list_booted_simulators | head -n 1 | cut -d'|' -f2)"
    fi
    if [[ -z "$SOURCE_UDID" ]]; then
      echo "No booted simulator found. Boot one and retry." >&2
      exit 1
    fi
    exec xcrun simctl spawn "$SOURCE_UDID" log stream --style "$LOG_STYLE" --level "$LOG_LEVEL" --predicate "$LOG_PREDICATE"
    ;;
  device)
    if [[ -z "$SOURCE_UDID" ]]; then
      SOURCE_UDID="$(list_physical_devices | head -n 1 | cut -d'|' -f2)"
    fi
    if [[ -z "$SOURCE_UDID" ]]; then
      echo "No connected iOS device found." >&2
      exit 1
    fi
    tmp_dir="$(mktemp -d)"
    archive_path="${tmp_dir}/device.logarchive"
    cleanup() {
      rm -rf "$tmp_dir"
    }
    trap cleanup EXIT
    /usr/bin/log collect --device-udid "$SOURCE_UDID" --last "$LOG_LAST" --output "$archive_path" --predicate "$LOG_PREDICATE" >/dev/null
    /usr/bin/log show --style "$LOG_STYLE" --predicate "$LOG_PREDICATE" "$archive_path"
    ;;
  *)
    echo "Unknown source kind: $SOURCE_KIND" >&2
    exit 2
    ;;
esac
