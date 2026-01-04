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
MLC_MACABI_CACHE_ROOT="${MLC_MACABI_CACHE_ROOT:-$ROOT_DIR/.mlc_llm_cache}"

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
  macabi_cache="$MLC_MACABI_CACHE_ROOT/$arch"
  echo "==> Build macabi libs ($arch, deployment $MLC_MACABI_DEPLOYMENT_TARGET)"
  MLC_MACABI_ARCH="$arch" \
  MLC_LLM_HOME="$macabi_cache" \
  MLC_JIT_POLICY=REDO \
  CMAKE_OSX_ARCHITECTURES="$arch" \
  "${MLC_LLM_CMD[@]}" package \
    --package-config "$ROOT_DIR/mlc-package-config-macabi.json" \
    --output "$macabi_out"
  echo "==> Patch model library metadata for xcframework packaging ($arch)"
  fix_model_lib_platform "$arch" "$macabi_out"
done

libs=(
  libmlc_llm.a
  libtvm_runtime.a
  libtvm_ffi_static.a
  libtokenizers_cpp.a
  libtokenizers_c.a
  libsentencepiece.a
  libmodel_iphone.a
)

mkdir -p "$XCFRAMEWORK_OUTPUT"

first_macabi_arch="${MLC_MACABI_ARCHS%% *}"
macabi_lib_root="$MACABI_OUTPUT/$first_macabi_arch/lib"
if [[ "$MLC_MACABI_ARCHS" == *" "* ]]; then
  macabi_universal_root="$MACABI_OUTPUT/universal/lib"
  mkdir -p "$macabi_universal_root"
  for lib in "${libs[@]}"; do
    inputs=()
    for arch in $MLC_MACABI_ARCHS; do
      inputs+=("$MACABI_OUTPUT/$arch/lib/$lib")
    done
    lipo -create "${inputs[@]}" -output "$macabi_universal_root/$lib"
  done
  macabi_lib_root="$macabi_universal_root"
fi

for lib in "${libs[@]}"; do
  out="$XCFRAMEWORK_OUTPUT/${lib%.a}.xcframework"
  rm -rf "$out"
  xcodebuild -create-xcframework \
    -library "$IPHONE_OUTPUT/lib/$lib" \
    -library "$macabi_lib_root/$lib" \
    -output "$out"
done

echo "==> XCFrameworks ready: $XCFRAMEWORK_OUTPUT"
