#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MLC_LLM_SOURCE_DIR="${MLC_LLM_SOURCE_DIR:-/Users/ronnie/Github/mlc-llm}"
if [[ ! -d "$MLC_LLM_SOURCE_DIR" ]]; then
  echo "error: MLC_LLM_SOURCE_DIR not found: $MLC_LLM_SOURCE_DIR" >&2
  exit 1
fi
export PYTHONPATH="$MLC_LLM_SOURCE_DIR/python:$MLC_LLM_SOURCE_DIR/3rdparty/tvm/python${PYTHONPATH:+:$PYTHONPATH}"
export TVM_LIBRARY_PATH="$MLC_LLM_SOURCE_DIR/3rdparty/tvm/build"
if command -v mlc_llm >/dev/null 2>&1; then
  MLC_LLM_CMD=(mlc_llm)
else
  MLC_LLM_CMD=(python3 -m mlc_llm)
fi

IPHONE_OUTPUT="${IPHONE_OUTPUT:-$ROOT_DIR/dist}"
MACABI_OUTPUT="${MACABI_OUTPUT:-$ROOT_DIR/dist-maccatalyst}"
XCFRAMEWORK_OUTPUT="${XCFRAMEWORK_OUTPUT:-$ROOT_DIR/dist/xcframeworks}"
MLC_MACABI_DEPLOYMENT_TARGET="${MLC_MACABI_DEPLOYMENT_TARGET:-18.0}"
MLC_MACABI_ARCHS="${MLC_MACABI_ARCHS:-arm64}"

export MLC_LLM_SOURCE_DIR
export MLC_MACABI_DEPLOYMENT_TARGET

fix_model_lib_platform() {
  local macabi_arch="$1"
  local macabi_output="$2"
  local tmpdir
  tmpdir="$(mktemp -d)"
  echo 'int mlc_model_dummy = 0;' > "$tmpdir/dummy.c"
  xcrun --sdk iphoneos clang -c "$tmpdir/dummy.c" \
    -target "arm64-apple-ios${MLC_MACABI_DEPLOYMENT_TARGET}" \
    -o "$tmpdir/dummy_ios.o"
  xcrun --sdk macosx clang -c "$tmpdir/dummy.c" \
    -target "${macabi_arch}-apple-ios${MLC_MACABI_DEPLOYMENT_TARGET}-macabi" \
    -o "$tmpdir/dummy_macabi.o"
  libtool -static -o "$IPHONE_OUTPUT/lib/libmodel_iphone.a" \
    "$tmpdir/dummy_ios.o" "$IPHONE_OUTPUT/lib/libmodel_iphone.a"
  libtool -static -o "$macabi_output/lib/libmodel_iphone.a" \
    "$tmpdir/dummy_macabi.o" "$macabi_output/lib/libmodel_iphone.a"
  rm -rf "$tmpdir"
}

echo "==> Build iphoneos libs"
"${MLC_LLM_CMD[@]}" package \
  --package-config "$ROOT_DIR/mlc-package-config.json" \
  --output "$IPHONE_OUTPUT"

for arch in $MLC_MACABI_ARCHS; do
  macabi_out="$MACABI_OUTPUT/$arch"
  echo "==> Build macabi libs ($arch, deployment $MLC_MACABI_DEPLOYMENT_TARGET)"
  CMAKE_OSX_ARCHITECTURES="$arch" "${MLC_LLM_CMD[@]}" package \
    --package-config "$ROOT_DIR/mlc-package-config-macabi.json" \
    --output "$macabi_out"
  echo "==> Patch model library metadata for xcframework packaging ($arch)"
  fix_model_lib_platform "$arch" "$macabi_out"
done

mkdir -p "$XCFRAMEWORK_OUTPUT"

libs=(
  libmlc_llm.a
  libtvm_runtime.a
  libtvm_ffi_static.a
  libtokenizers_cpp.a
  libtokenizers_c.a
  libsentencepiece.a
  libmodel_iphone.a
)

for lib in "${libs[@]}"; do
  out="$XCFRAMEWORK_OUTPUT/${lib%.a}.xcframework"
  rm -rf "$out"
  macabi_args=()
  for arch in $MLC_MACABI_ARCHS; do
    macabi_args+=("-library" "$MACABI_OUTPUT/$arch/lib/$lib")
  done
  xcodebuild -create-xcframework \
    -library "$IPHONE_OUTPUT/lib/$lib" \
    "${macabi_args[@]}" \
    -output "$out"
done

echo "==> XCFrameworks ready: $XCFRAMEWORK_OUTPUT"
