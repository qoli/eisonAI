#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_OUTPUT_DIR="${PROJECT_ROOT}/logs/xcode"
DEFAULT_PROJECT_PATH="${PROJECT_ROOT}/eisonAI.xcodeproj"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
PROJECT_PATH=""
WAIT_SECONDS="0.5"

usage() {
  cat <<'EOF'
Usage: Scripts/export_xcode_console.sh [options]

Export the visible Xcode debug console content to a timestamped log file.

Options:
  --output-dir PATH  Directory for exported logs.
                     Default: ./logs/xcode
  --project PATH     Optionally open a .xcodeproj or .xcworkspace before export.
  --wait SECONDS     Seconds to wait after opening/focusing Xcode. Default: 0.5
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { echo "[ERROR] Missing value for --output-dir" >&2; exit 1; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --project)
      [[ $# -ge 2 ]] || { echo "[ERROR] Missing value for --project" >&2; exit 1; }
      PROJECT_PATH="$2"
      shift 2
      ;;
    --wait)
      [[ $# -ge 2 ]] || { echo "[ERROR] Missing value for --wait" >&2; exit 1; }
      WAIT_SECONDS="$2"
      shift 2
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

if [[ ! -d /Applications/Xcode.app ]]; then
  echo "[ERROR] Xcode is not installed at /Applications/Xcode.app" >&2
  exit 1
fi

if [[ -n "${PROJECT_PATH}" ]]; then
  if [[ "${PROJECT_PATH}" != /* ]]; then
    PROJECT_PATH="${PWD}/${PROJECT_PATH}"
  fi
  if [[ ! -e "${PROJECT_PATH}" ]]; then
    echo "[ERROR] Xcode project or workspace not found: ${PROJECT_PATH}" >&2
    exit 1
  fi
else
  PROJECT_PATH="${DEFAULT_PROJECT_PATH}"
fi

if [[ "${OUTPUT_DIR}" != /* ]]; then
  OUTPUT_DIR="${PWD}/${OUTPUT_DIR}"
fi

mkdir -p "${OUTPUT_DIR}"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_PATH="${OUTPUT_DIR}/${TIMESTAMP}.log"

echo "[INFO] Exporting Xcode console to ${OUTPUT_PATH}"

CONSOLE_TEXT="$(
  osascript - "${PROJECT_PATH}" "${WAIT_SECONDS}" <<'APPLESCRIPT'
on run argv
  set projectPath to item 1 of argv
  set waitSeconds to (item 2 of argv) as number

  tell application "Xcode"
    activate
    if (count of windows) is 0 then
      open POSIX file projectPath
      delay waitSeconds
    end if
  end tell

  delay waitSeconds

  tell application "System Events"
    tell process "Xcode"
      set frontmost to true

      set debugAreaMenu to menu 1 of menu item "Debug Area" of menu "View" of menu bar item "View" of menu bar 1
      if exists menu item "Show Debug Area" of debugAreaMenu then
        click menu item "Show Debug Area" of debugAreaMenu
        delay 0.2
      end if
      click menu item "Activate Console" of debugAreaMenu
      delay 0.2

      set focusedItem to value of attribute "AXFocusedUIElement"
      set itemRole to value of attribute "AXRole" of focusedItem
      if itemRole is not "AXTextArea" then
        error "Focused Xcode element is not the debug console text area."
      end if

      set consoleText to value of attribute "AXValue" of focusedItem
      return consoleText
    end tell
  end tell
end run
APPLESCRIPT
)"

if [[ -z "${CONSOLE_TEXT}" ]]; then
  echo "[ERROR] Xcode console is empty or unavailable" >&2
  exit 1
fi

printf '%s\n' "${CONSOLE_TEXT}" > "${OUTPUT_PATH}"

BYTES_WRITTEN="$(wc -c < "${OUTPUT_PATH}" | tr -d ' ')"
echo "[INFO] Wrote ${BYTES_WRITTEN} bytes"
echo "${OUTPUT_PATH}"

