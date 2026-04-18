#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_PATH="${PROJECT_ROOT}/eisonAI.xcodeproj"
TARGET_PATH="${DEFAULT_PATH}"
WAIT_SECONDS="3"
OPEN_ONLY="0"

usage() {
  cat <<'EOF'
Usage: Scripts/run_xcode.sh [options]

Open an Xcode project or workspace and optionally trigger Run via Cmd-R.

Options:
  --path PATH     Path to a .xcodeproj or .xcworkspace.
                  Default: ./eisonAI.xcodeproj
  --wait SECONDS  Seconds to wait before sending Cmd-R. Default: 3
  --open-only     Open Xcode and the project, but do not trigger Run
  -h, --help      Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      [[ $# -ge 2 ]] || { echo "[ERROR] Missing value for --path" >&2; exit 1; }
      TARGET_PATH="$2"
      shift 2
      ;;
    --wait)
      [[ $# -ge 2 ]] || { echo "[ERROR] Missing value for --wait" >&2; exit 1; }
      WAIT_SECONDS="$2"
      shift 2
      ;;
    --open-only)
      OPEN_ONLY="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "${WAIT_SECONDS}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "[ERROR] --wait must be a non-negative number: ${WAIT_SECONDS}" >&2
  exit 1
fi

if [[ "${TARGET_PATH}" != /* ]]; then
  TARGET_PATH="${PWD}/${TARGET_PATH}"
fi

if [[ ! -e "${TARGET_PATH}" ]]; then
  echo "[ERROR] Xcode project or workspace not found: ${TARGET_PATH}" >&2
  exit 1
fi

ABS_TARGET_PATH="$(cd "$(dirname "${TARGET_PATH}")" && pwd)/$(basename "${TARGET_PATH}")"

if [[ ! -d /Applications/Xcode.app ]]; then
  echo "[ERROR] Xcode is not installed at /Applications/Xcode.app" >&2
  exit 1
fi

echo "[INFO] Opening ${ABS_TARGET_PATH}"
if [[ "${OPEN_ONLY}" == "1" ]]; then
  echo "[INFO] open-only mode enabled"
else
  echo "[INFO] Waiting ${WAIT_SECONDS}s before sending Cmd-R"
fi

osascript - "${ABS_TARGET_PATH}" "${WAIT_SECONDS}" "${OPEN_ONLY}" <<'APPLESCRIPT'
on run argv
  set targetPath to item 1 of argv
  set waitSeconds to (item 2 of argv) as number
  set openOnly to item 3 of argv

  tell application "Xcode"
    activate
    open POSIX file targetPath
  end tell

  delay waitSeconds

  if openOnly is "1" then
    return "opened"
  end if

  tell application "System Events"
    tell process "Xcode"
      set frontmost to true
      keystroke "r" using command down
    end tell
  end tell

  return "opened_and_ran"
end run
APPLESCRIPT

