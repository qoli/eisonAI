# MLC-LLM 調用資料（EisonAI）

本文件整理 EisonAI 專案中與 `mlc-llm` 相關的「路徑、指令、產物」與更新流程，方便後續維護與交接。

## mlc-llm 專案位置

- 本機路徑：`/Users/ronnie/Github/mlc-llm`
- Xcode local package（MLC Swift SDK）來源：`/Users/ronnie/Github/mlc-llm/ios/MLCSwift`
- 打包指令使用的 env：
  - `MLC_LLM_SOURCE_DIR=/Users/ronnie/Github/mlc-llm`

## 主要指令：產出 iOS 連結用靜態庫（dist/lib）

在 EisonAI repo 根目錄執行：

```bash
MLC_LLM_SOURCE_DIR=/Users/ronnie/Github/mlc-llm mlc_llm package
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

## Mac Catalyst（macabi，Apple Silicon）

在 EisonAI repo 根目錄執行：

```bash
MLC_LLM_SOURCE_DIR=/Users/ronnie/Github/mlc-llm \
MLC_MACABI_DEPLOYMENT_TARGET=18.0 \
mlc_llm package --package-config mlc-package-config-macabi.json --output dist-maccatalyst
```

產物：

- `dist-maccatalyst/lib/`：macabi 靜態庫（arm64）
- `dist/xcframeworks/`：iphoneos + macabi slices 合併後的 `.xcframework`（供 Xcode link）

一鍵腳本（建議使用 Python 3.12 venv 執行）：

```bash
source .venv-mlc312/bin/activate
Scripts/build_mlc_xcframeworks.sh
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
