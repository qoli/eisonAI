#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEVICE=""
SOURCE="catalog"
AUTO_SELECT="1"
WAIT_BEFORE_RUN="1"
WAIT_AFTER_RUN="8"
LOG_SECONDS="45"
ECHO_LOGS="0"
REPO_ID=""

usage() {
  cat <<'EOF'
Usage:
  Scripts/test_mlx_download_deeplink.sh <repo-id> [options]

Options:
  --device <selector>       Device name or UDID passed to run_ios_device_debug.py
  --source <catalog|custom> Deeplink source flag. Default: catalog
  --auto-select <0|1>       Whether to auto-select on completion. Default: 1
  --wait-before-run <sec>   Wait before sending Cmd-R to Xcode. Default: 1
  --wait-after-run <sec>    Wait after Xcode Run before firing deeplink. Default: 8
  --log-seconds <sec>       Seconds to capture device logs. Default: 45
  --echo-logs               Mirror device logs to stdout
  -h, --help                Show this help

Example:
  Scripts/test_mlx_download_deeplink.sh mlx-community/Qwen3-0.6B-4bit
  Scripts/test_mlx_download_deeplink.sh mlx-community/Qwen3-0.6B-4bit --device 'My iPhone' --source catalog
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE="${2:?missing device value}"
      shift 2
      ;;
    --source)
      SOURCE="${2:?missing source value}"
      shift 2
      ;;
    --auto-select)
      AUTO_SELECT="${2:?missing auto-select value}"
      shift 2
      ;;
    --wait-before-run)
      WAIT_BEFORE_RUN="${2:?missing wait-before-run value}"
      shift 2
      ;;
    --wait-after-run)
      WAIT_AFTER_RUN="${2:?missing wait-after-run value}"
      shift 2
      ;;
    --log-seconds)
      LOG_SECONDS="${2:?missing log-seconds value}"
      shift 2
      ;;
    --echo-logs)
      ECHO_LOGS="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "[ERROR] Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "$REPO_ID" ]]; then
        echo "[ERROR] Unexpected extra argument: $1" >&2
        usage
        exit 1
      fi
      REPO_ID="$1"
      shift
      ;;
  esac
done

if [[ -z "$REPO_ID" ]]; then
  echo "[ERROR] Missing repo ID." >&2
  usage
  exit 1
fi

if [[ "$SOURCE" != "catalog" && "$SOURCE" != "custom" ]]; then
  echo "[ERROR] --source must be catalog or custom." >&2
  exit 1
fi

if [[ "$AUTO_SELECT" != "0" && "$AUTO_SELECT" != "1" ]]; then
  echo "[ERROR] --auto-select must be 0 or 1." >&2
  exit 1
fi

ENCODED_REPO_ID="$(python3 - <<'PY' "$REPO_ID"
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
)"

DEEPLINK="eisonai://mlx-download?repo=${ENCODED_REPO_ID}&source=${SOURCE}&autoSelect=${AUTO_SELECT}"

echo "[INFO] Running Xcode on the currently selected scheme/destination..."
"$REPO_ROOT/Scripts/run_xcode.sh" --wait "$WAIT_BEFORE_RUN"

echo "[INFO] Waiting ${WAIT_AFTER_RUN}s for Xcode Run to finish launching..."
sleep "$WAIT_AFTER_RUN"

echo "[INFO] Triggering deeplink: $DEEPLINK"

DEVICE_ARGS=()
if [[ -n "$DEVICE" ]]; then
  DEVICE_ARGS+=(--device "$DEVICE")
fi

LOG_ARGS=()
if [[ "$ECHO_LOGS" == "1" ]]; then
  LOG_ARGS+=(--echo-logs)
fi

cd "$REPO_ROOT"
python3 Scripts/run_ios_device_debug.py \
  "${DEVICE_ARGS[@]}" \
  --skip-build \
  --skip-install \
  --payload-url "$DEEPLINK" \
  --log-seconds "$LOG_SECONDS" \
  "${LOG_ARGS[@]}"
