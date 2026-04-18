#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_SCHEME_FILE="$REPO_ROOT/eisonAI.xcodeproj/xcshareddata/xcschemes/iOS.xcscheme"

SOURCE="catalog"
AUTO_SELECT="1"
PURGE_EXISTING="1"
ROUTE="page"
WAIT_BEFORE_RUN="1"
WAIT_BEFORE_EXPORT="45"
CONSOLE_WAIT="0.5"
SCHEME_FILE="$DEFAULT_SCHEME_FILE"
REPO_ID=""
REUSE_OPEN_XCODE="0"

usage() {
  cat <<EOF
Usage:
  Scripts/test_mlx_download_deeplink.sh <repo-id> [options]

Options:
  --source <catalog|custom>   Startup trigger source flag. Default: catalog
  --auto-select <0|1>         Whether to auto-select on completion. Default: 1
  --purge-existing <0|1>      Delete local MLX artifacts before launch. Default: 1
  --route <page|direct>       Automation route. Default: page
  --wait-before-run <sec>     Wait before sending Cmd-R to Xcode. Default: 1
  --wait-before-export <sec>  Wait after Xcode Run before exporting console. Default: 45
  --console-wait <sec>        Wait passed to export_xcode_console.sh. Default: 0.5
  --scheme-file <path>        Scheme file to patch. Default: $DEFAULT_SCHEME_FILE
  --reuse-open-xcode          Do not restart Xcode before Run. Default: restart for reliability
  -h, --help                  Show this help

Example:
  Scripts/test_mlx_download_deeplink.sh mlx-community/Qwen3-0.6B-4bit
  Scripts/test_mlx_download_deeplink.sh my-org/custom-model --source custom --auto-select 0
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="${2:?missing source value}"
      shift 2
      ;;
    --auto-select)
      AUTO_SELECT="${2:?missing auto-select value}"
      shift 2
      ;;
    --purge-existing)
      PURGE_EXISTING="${2:?missing purge-existing value}"
      shift 2
      ;;
    --route)
      ROUTE="${2:?missing route value}"
      shift 2
      ;;
    --wait-before-run)
      WAIT_BEFORE_RUN="${2:?missing wait-before-run value}"
      shift 2
      ;;
    --wait-before-export)
      WAIT_BEFORE_EXPORT="${2:?missing wait-before-export value}"
      shift 2
      ;;
    --console-wait)
      CONSOLE_WAIT="${2:?missing console-wait value}"
      shift 2
      ;;
    --scheme-file)
      SCHEME_FILE="${2:?missing scheme-file value}"
      shift 2
      ;;
    --reuse-open-xcode)
      REUSE_OPEN_XCODE="1"
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

if [[ "$PURGE_EXISTING" != "0" && "$PURGE_EXISTING" != "1" ]]; then
  echo "[ERROR] --purge-existing must be 0 or 1." >&2
  exit 1
fi

if [[ "$ROUTE" != "page" && "$ROUTE" != "direct" ]]; then
  echo "[ERROR] --route must be page or direct." >&2
  exit 1
fi

if [[ ! -f "$SCHEME_FILE" ]]; then
  echo "[ERROR] Scheme file not found: $SCHEME_FILE" >&2
  exit 1
fi

BACKUP_FILE="$(mktemp "${TMPDIR:-/tmp}/mlx-deeplink-scheme.XXXXXX")"
cp "$SCHEME_FILE" "$BACKUP_FILE"

restore_scheme() {
  cp "$BACKUP_FILE" "$SCHEME_FILE"
  rm -f "$BACKUP_FILE"
}

trap restore_scheme EXIT

python3 - <<'PY' "$SCHEME_FILE" "$REPO_ID" "$SOURCE" "$AUTO_SELECT" "$PURGE_EXISTING" "$ROUTE"
import sys
import xml.etree.ElementTree as ET

scheme_path, repo_id, source, auto_select, purge_existing, route = sys.argv[1:7]
tree = ET.parse(scheme_path)
root = tree.getroot()
launch_action = root.find("LaunchAction")
if launch_action is None:
    raise SystemExit("[ERROR] LaunchAction not found in scheme")

args = launch_action.find("CommandLineArguments")
if args is None:
    args = ET.SubElement(launch_action, "CommandLineArguments")

arg_values = {
    "-eisonai-debug-mlx-route": route,
    "-eisonai-debug-mlx-download-repo": repo_id,
    "-eisonai-debug-mlx-download-source": source,
    "-eisonai-debug-mlx-download-auto-select": auto_select,
    "-eisonai-debug-mlx-purge-existing": purge_existing,
}

desired_pairs = set()
for flag, value in arg_values.items():
    desired_pairs.add(flag)
    desired_pairs.add(value)

for candidate in list(args.findall("CommandLineArgument")):
    if candidate.get("argument") in desired_pairs:
        args.remove(candidate)

for flag, value in arg_values.items():
    flag_node = ET.SubElement(args, "CommandLineArgument")
    flag_node.set("argument", flag)
    flag_node.set("isEnabled", "YES")

    value_node = ET.SubElement(args, "CommandLineArgument")
    value_node.set("argument", value)
    value_node.set("isEnabled", "YES")

envs = launch_action.find("EnvironmentVariables")
if envs is not None:
    debug_keys = {
        "EISONAI_DEBUG_MLX_ROUTE",
        "EISONAI_DEBUG_MLX_DOWNLOAD_REPO",
        "EISONAI_DEBUG_MLX_DOWNLOAD_SOURCE",
        "EISONAI_DEBUG_MLX_DOWNLOAD_AUTO_SELECT",
        "EISONAI_DEBUG_MLX_PURGE_EXISTING",
    }
    for candidate in list(envs.findall("EnvironmentVariable")):
        if candidate.get("key") in debug_keys:
            envs.remove(candidate)

ET.indent(tree, space="   ")
tree.write(scheme_path, encoding="UTF-8", xml_declaration=True)
PY

echo "[INFO] Patched scheme command line arguments in $SCHEME_FILE"
echo "[INFO] route=$ROUTE repo=$REPO_ID source=$SOURCE autoSelect=$AUTO_SELECT purgeExisting=$PURGE_EXISTING"

if [[ "$REUSE_OPEN_XCODE" != "1" ]]; then
  echo "[INFO] Restarting Xcode so the updated scheme arguments are reloaded"
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
if application "Xcode" is running then
  tell application "Xcode" to activate
  tell application "System Events"
    keystroke "q" using command down
  end tell
end if
APPLESCRIPT
  for _ in {1..8}; do
    if ! pgrep -x "Xcode" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if pgrep -x "Xcode" >/dev/null 2>&1; then
    echo "[WARN] Xcode did not quit after Cmd-Q; sending SIGTERM"
    pkill -TERM -x "Xcode" || true
  fi
  for _ in {1..8}; do
    if ! pgrep -x "Xcode" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if pgrep -x "Xcode" >/dev/null 2>&1; then
    echo "[WARN] Xcode still running after SIGTERM; sending SIGKILL"
    pkill -KILL -x "Xcode" || true
  fi
  for _ in {1..8}; do
    if ! pgrep -x "Xcode" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

"$REPO_ROOT/Scripts/run_xcode.sh" --wait "$WAIT_BEFORE_RUN"

echo "[INFO] Waiting ${WAIT_BEFORE_EXPORT}s before exporting Xcode console..."
sleep "$WAIT_BEFORE_EXPORT"

CONSOLE_OUTPUT="$("$REPO_ROOT/Scripts/export_xcode_console.sh" --wait "$CONSOLE_WAIT")"
echo "$CONSOLE_OUTPUT"
