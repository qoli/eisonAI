#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

VENV_PATH="${VENV_PATH:-$ROOT_DIR/.venv-mlc312}"
if [[ -f "$VENV_PATH/bin/activate" ]]; then
  # shellcheck disable=SC1090
  source "$VENV_PATH/bin/activate"
else
  echo "error: venv not found at $VENV_PATH" >&2
  echo "hint: create it or set VENV_PATH to the correct location" >&2
  exit 1
fi

if [[ -z "${MLC_LLM_SOURCE_DIR:-}" ]]; then
  DEFAULT_MLC_LLM_SOURCE_DIR="/Volumes/Data/Github/mlc-llm"
  if [[ -d "$DEFAULT_MLC_LLM_SOURCE_DIR" ]]; then
    MLC_LLM_SOURCE_DIR="$DEFAULT_MLC_LLM_SOURCE_DIR"
    export MLC_LLM_SOURCE_DIR
  else
    echo "error: MLC_LLM_SOURCE_DIR not set and default not found: $DEFAULT_MLC_LLM_SOURCE_DIR" >&2
    exit 1
  fi
fi

export MLC_MACABI_ARCHS="${MLC_MACABI_ARCHS:-arm64 x86_64}"

cd "$ROOT_DIR"
echo "Build targets: iphoneos + macabi (${MLC_MACABI_ARCHS})"
echo "Stages:"
echo "  1) iphoneos"
stage_index=2
for arch in $MLC_MACABI_ARCHS; do
  echo "  ${stage_index}) macabi (${arch})"
  stage_index=$((stage_index + 1))
done
echo "  ${stage_index}) xcframework packaging"
Scripts/build_mlc_xcframeworks.sh

SRC_CONFIG="$ROOT_DIR/dist/bundle/mlc-app-config.json"
DST_CONFIG="$ROOT_DIR/iOS (App)/Config/mlc-app-config.json"
if [[ -f "$SRC_CONFIG" ]]; then
  cp -f "$SRC_CONFIG" "$DST_CONFIG"
  echo "Synced: $SRC_CONFIG -> $DST_CONFIG"
else
  echo "warning: missing $SRC_CONFIG (skip sync)" >&2
fi
