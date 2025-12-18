#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CONDA_ENV_NAME="${CONDA_ENV_NAME:-mlc-chat-venv}"
MLC_LLM_SOURCE_DIR="${MLC_LLM_SOURCE_DIR:-/Users/ronnie/Github/mlc-llm}"
MLC_JIT_POLICY="${MLC_JIT_POLICY:-ON}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"

IOS_MODEL_INPUT="${IOS_MODEL_INPUT:-/Volumes/Data/Github/eisonAI/dist/bundle/Qwen3-0.6B-q4f16_1-MLC}"
WEB_MODEL_INPUT="${WEB_MODEL_INPUT:-/Volumes/Data/Github/eisonAI/Shared (Extension)/Resources/webllm-assets/models/Qwen3-0.6B-q4f16_1-MLC}"

die() {
  echo "error: $*" >&2
  exit 1
}

info() {
  echo "==> $*" >&2
}

resolve_model_dir() {
  local input="$1"
  local candidate=""

  if [[ -d "$input" && -f "$input/mlc-chat-config.json" ]]; then
    candidate="$input"
  elif [[ -d "$input/resolve/main" && -f "$input/resolve/main/mlc-chat-config.json" ]]; then
    candidate="$input/resolve/main"
  elif [[ -d "$ROOT_DIR/$input" && -f "$ROOT_DIR/$input/mlc-chat-config.json" ]]; then
    candidate="$ROOT_DIR/$input"
  elif [[ -d "$ROOT_DIR/$input/resolve/main" && -f "$ROOT_DIR/$input/resolve/main/mlc-chat-config.json" ]]; then
    candidate="$ROOT_DIR/$input/resolve/main"
  else
    die "cannot find mlc-chat-config.json under: $input (or resolve/main)"
  fi

  if [[ ! -f "$candidate/tensor-cache.json" ]]; then
    die "missing tensor-cache.json in: $candidate"
  fi

  echo "$candidate"
}

run_mlc_chat_smoke() {
  local label="$1"
  local model_dir="$2"

  info "Smoke test ($label): $model_dir"

  # Use a pseudo-tty so prompt_toolkit-based `mlc_llm chat` can run non-interactively.
  python3 - "$CONDA_ENV_NAME" "$MLC_LLM_SOURCE_DIR" "$MLC_JIT_POLICY" "$TIMEOUT_SECONDS" "$model_dir" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

conda_env = sys.argv[1]
mlc_llm_source_dir = sys.argv[2]
mlc_jit_policy = sys.argv[3]
timeout_seconds = int(sys.argv[4])
model_dir = sys.argv[5]

env = os.environ.copy()
env["TERM"] = env.get("TERM", "xterm-256color")
env["MLC_LLM_SOURCE_DIR"] = mlc_llm_source_dir
env["MLC_JIT_POLICY"] = mlc_jit_policy
env.setdefault("MLC_DOWNLOAD_CACHE_POLICY", "OFF")

cmd = [
    "conda",
    "run",
    "-n",
    conda_env,
    "mlc_llm",
    "chat",
    model_dir,
    "--device",
    "metal",
    "--overrides",
    "context_window_size=2048;prefill_chunk_size=128",
]

master_fd, slave_fd = pty.openpty()
proc = subprocess.Popen(
    cmd,
    stdin=slave_fd,
    stdout=slave_fd,
    stderr=slave_fd,
    env=env,
    close_fds=True,
)
os.close(slave_fd)

start = time.time()
sent = False
buf = b""

try:
    while True:
        if time.time() - start > timeout_seconds:
            proc.kill()
            raise SystemExit(f"timeout after {timeout_seconds}s: {' '.join(cmd)}")

        r, _, _ = select.select([master_fd], [], [], 0.2)
        if master_fd in r:
            chunk = os.read(master_fd, 65536)
            if chunk:
                buf += chunk
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()

        # After startup, issue a short command sequence to ensure we can actually generate tokens.
        if not sent and time.time() - start > 2.0:
            os.write(master_fd, b"/set max_tokens=16\n")
            os.write(master_fd, b"Hello\n")
            os.write(master_fd, b"/exit\n")
            sent = True

        ret = proc.poll()
        if ret is not None:
            # Drain remaining output (best-effort)
            while True:
                r, _, _ = select.select([master_fd], [], [], 0.1)
                if master_fd not in r:
                    break
                chunk = os.read(master_fd, 65536)
                if not chunk:
                    break
                buf += chunk
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
            if ret != 0:
                raise SystemExit(ret)
            break
finally:
    try:
        os.close(master_fd)
    except OSError:
        pass
PY

  info "OK ($label)"
}

command -v conda >/dev/null 2>&1 || die "conda not found on PATH"
[[ -d "$MLC_LLM_SOURCE_DIR" ]] || die "MLC_LLM_SOURCE_DIR not found: $MLC_LLM_SOURCE_DIR"

IOS_MODEL_DIR="$(resolve_model_dir "$IOS_MODEL_INPUT")"
WEB_MODEL_DIR="$(resolve_model_dir "$WEB_MODEL_INPUT")"

run_mlc_chat_smoke "ios-dist-bundle" "$IOS_MODEL_DIR"
run_mlc_chat_smoke "web-llm-assets" "$WEB_MODEL_DIR"

info "All model smoke tests passed."
