# MLC-LLM 調用資料（EisonAI）

本文件整理 EisonAI 專案中與 `mlc-llm` 相關的「路徑、指令、產物」與更新流程，方便後續維護與交接。

## mlc-llm 專案位置

- 本機路徑：`/Volumes/Data/Github/mlc-llm`
- Xcode local package（MLC Swift SDK）來源：`/Volumes/Data/Github/mlc-llm/ios/MLCSwift`
- 打包指令使用的 env：
  - `MLC_LLM_SOURCE_DIR=/Volumes/Data/Github/mlc-llm`

## 主要指令：產出 iOS 連結用靜態庫（dist/lib）

在 EisonAI repo 根目錄執行：

```bash
MLC_LLM_SOURCE_DIR=/Volumes/Data/Github/mlc-llm mlc_llm package
```

### 依據的設定檔

- `mlc-package-config.json`：提供 `mlc_llm package` 的打包設定

### 產物

  - `dist/lib/`（重要）：iphoneos 靜態庫（例如 `libmlc_llm.a`、`libtvm_runtime.a`、`libtvm_ffi_static.a`…）
  - `dist/bundle/`（輔助/檢查用）：包含 `mlc-app-config.json`、模型資料夾（tokenizer/weights/config 等）

注意：

- `dist/lib/*.a` 為 iphoneos（arm64）靜態庫：
  - ✅ iPhone/iPad 真機
  - ✅ My Mac (Designed for iPad)
  - ❌ iOS Simulator

## Mac Catalyst（macabi，Apple Silicon + Intel）

在 EisonAI repo 根目錄執行：

```bash
MLC_LLM_SOURCE_DIR=/Volumes/Data/Github/mlc-llm \
MLC_MACABI_DEPLOYMENT_TARGET=18.0 \
MLC_MACABI_ARCHS="arm64 x86_64" \
mlc_llm package --package-config mlc-package-config-macabi.json --output dist-maccatalyst
```

產物：

- `dist-maccatalyst/lib/`：macabi 靜態庫（arm64）
- `dist/xcframeworks/`：iphoneos + macabi（arm64/x86_64） slices 合併後的 `.xcframework`（供 Xcode link）

一鍵腳本（建議使用 Python 3.12 venv 執行）：

```bash
source .venv-mlc312/bin/activate
MLC_MACABI_ARCHS="arm64 x86_64" Scripts/build_mlc_xcframeworks.sh
```

## iOS app 端的模型設定（model_id / model_lib）

EisonAI 的原生 MLC demo 需要 `model_lib`（hash 字串），來源是 `mlc_llm package` 產出的 `dist/bundle/mlc-app-config.json`。

- 目標檔：`iOS (App)/Config/mlc-app-config.json`
- 同步方式：從 `dist/bundle/mlc-app-config.json` 複製對應 model record 的
  - `model_id`
  - `model_lib`
  - `model_path`（通常等於 `model_id`）

## iOS app 端的模型檔案（weights/tokenizer/config）

原生 MLC demo **不使用** `dist/bundle/<model>` 內的 weights；模型檔案統一使用 extension 的 `webllm-assets`（同一份模型同時供 WebLLM 與原生 MLC demo 使用）。

- WebLLM assets 路徑：`Shared (Extension)/Resources/webllm-assets/`
- iOS app 讀取方式：從 Embedded Extension（`.appex`）內唯讀存取 `webllm-assets/models/<model>/resolve/main`

## WebLLM wasm（WebGPU）編譯流程（Qwen3-0.6B cs2k）

目標：產出 `Qwen3-0.6B-q4f16_1-ctx4k_cs2k-webgpu.wasm`，供 Safari Extension 使用。

### 1) 安裝 emsdk（建議 3.1.56）

```bash
git clone https://github.com/emscripten-core/emsdk.git /tmp/emsdk
cd /tmp/emsdk
./emsdk install 3.1.56
./emsdk activate 3.1.56
source /tmp/emsdk/emsdk_env.sh
```

### 2) 準備 wasm runtime（MLC + TVM）

```bash
export MLC_LLM_SOURCE_DIR=/Volumes/Data/Github/mlc-llm
export TVM_SOURCE_DIR=/Volumes/Data/Github/mlc-llm/3rdparty/tvm
export TVM_HOME=/Volumes/Data/Github/mlc-llm/3rdparty/tvm
cd /Volumes/Data/Github/mlc-llm
./web/prep_emcc_deps.sh
```

### 3) 安裝 mlc-llm CLI（建議用 venv）

```bash
python3.11 -m venv /tmp/mlc-llm-venv311
source /tmp/mlc-llm-venv311/bin/activate
python -m pip install --pre -U -f https://mlc.ai/wheels mlc-llm-nightly-cpu mlc-ai-nightly-cpu
```

### 4) 編譯 wasm（cs2k）

```bash
source /tmp/emsdk/emsdk_env.sh
export MLC_LLM_SOURCE_DIR=/Volumes/Data/Github/mlc-llm
export TVM_SOURCE_DIR=/Volumes/Data/Github/mlc-llm/3rdparty/tvm
export TVM_HOME=/Volumes/Data/Github/mlc-llm/3rdparty/tvm
/tmp/mlc-llm-venv311/bin/python -m mlc_llm compile \
  "Shared (Extension)/Resources/webllm-assets/models/Qwen3-0.6B-q4f16_1-MLC/resolve/main/mlc-chat-config.json" \
  --device webgpu \
  --overrides "context_window_size=4096;prefill_chunk_size=2048" \
  --output "Shared (Extension)/Resources/webllm-assets/wasm/Qwen3-0.6B-q4f16_1-ctx4k_cs2k-webgpu.wasm"
```

### 5) Extension 內對應檔名

- `Shared (Extension)/Resources/webllm/popup.js`
  - `WASM_FILE = "Qwen3-0.6B-q4f16_1-ctx4k_cs2k-webgpu.wasm"`
- `Scripts/download_webllm_assets.py`
  - `WEBLLM_WASM_FILE = "Qwen3-0.6B-q4f16_1-ctx4k_cs2k-webgpu.wasm"`

> `webllm-assets/wasm/` 為 gitignored；若需多人同步，請自行提供 wasm 下載來源或改用內部分發。

## 常見 Crash 排查（Runtime / Loader）

### 症狀 1：`Cannot find system lib ...`
代表 `model_lib` 沒有被連結進 App binary。

**檢查 / 修正：**
- `mlc-app-config.json` 的 `model_lib` 必須與 `libmodel_iphone` 內實際符號一致
- Xcode target 要 force-load `libmodel_iphone`（避免 dead-strip）
  - `OTHER_LDFLAGS[sdk=iphoneos*]` 加上  
    `-Wl,-force_load,$(PROJECT_DIR)/dist/xcframeworks/libmodel_iphone.xcframework/ios-arm64/libmodel_iphone.a`
  - `OTHER_LDFLAGS[sdk=macosx*]` 加上  
    `-Wl,-force_load,$(PROJECT_DIR)/dist/xcframeworks/libmodel_iphone.xcframework/ios-arm64-maccatalyst/libmodel_iphone.a`

### 症狀 1b（TestFlight / Archive 才出現）：`Missing model lib ...`
代表 **Archive/Export strip 掉 global symbol**，`dlsym` 找不到 model lib。

修正重點（Release target）：
- 保留 symbol（linker flags）
  - `-Wl,-u,_qwen3_q4f16_1_37d26ba247cc02f647af18ad629c48d2___tvm_ffi__library_bin`
  - `-Wl,-exported_symbols_list,$(PROJECT_DIR)/Scripts/mlc_exported_symbols.txt`
  - `-Wl,-export_dynamic`
  - `-Wl,-exported_symbol,_qwen3_q4f16_1_37d26ba247cc02f647af18ad629c48d2___tvm_ffi__library_bin`
- 避免 archive 時把 global symbol 全剝掉
  - `STRIP_STYLE = non-global`
  - `STRIP_INSTALLED_PRODUCT = NO`
- 強制硬引用（防止 link 被移除）
  - 新增 `iOS (App)/Shared/MLC/MLCModelLibKeep.m`

驗證：
- fastlane 打包後自動檢查 IPA/PKG 是否含有 symbol  
  `fastlane/Fastfile` 的 `verify_model_lib_symbol!` 會解包並 `nm -gU` 搜索 symbol。  

### 症狀 2：`Library binary was created using {relax.VMExecutable} but a loader of that name is not registered`
代表 **model lib 與 runtime 版本不一致**，或 `libtvm_runtime` 被 dead-strip。

**建議修正：**
1) 用同一份 `mlc-llm` 重新產生整套 xcframeworks  
   ```
   source .venv-mlc312/bin/activate
   MLC_LLM_SOURCE_DIR=/Users/ronnie/Github/mlc-llm Scripts/build_mlc_xcframeworks.sh
   ```
2) Xcode Clean Build Folder 再重編
3) 強制連結 `libtvm_runtime`（避免 loader 註冊被裁掉）
   - `OTHER_LDFLAGS[sdk=iphoneos*]` 加上  
     `-Wl,-force_load,$(PROJECT_DIR)/dist/xcframeworks/libtvm_runtime.xcframework/ios-arm64/libtvm_runtime.a`
   - `OTHER_LDFLAGS[sdk=macosx*]` 加上  
     `-Wl,-force_load,$(PROJECT_DIR)/dist/xcframeworks/libtvm_runtime.xcframework/ios-arm64-maccatalyst/libtvm_runtime.a`
