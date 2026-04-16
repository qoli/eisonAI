## 未發佈 - 2026-01-09

### ⚡ 效能改善
- **原生 MLC 推理優化**: 調整 `prefill_chunk_size=3400` 與 `context_window_size=4096`，改善長輸入延遲

### 🔧 技術改進
- **xcframeworks 重新打包**: 產出包含 macCatalyst `arm64 + x86_64` 的通用 slices
- **MLC 打包流程規範**: 更新 `Spec/MLC_LLM.md`，明確要求每次更新需包含 x86_64
- **App 設定同步**: 同步 `dist/bundle/mlc-app-config.json` 至 app 端設定檔
