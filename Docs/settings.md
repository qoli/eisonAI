# Settings（已移除）

本專案已全面遷移至 **WebLLM popup 推理 + bundled assets** 的方案，因此舊版的 Settings 頁面（API URL/Key、遠端模型、提示詞管理等）已不再存在。

## 目前要調整什麼？

- 摘要 prompt：請直接修改 `Shared (Extension)/Resources/webllm/popup.js` 的 `buildSummaryMessages(...)`
- 模型與 wasm：以 assets 打包方式管理（見 `Shared (Extension)/Resources/webllm-assets/README.md`）

## 如果未來要恢復「可設定」能力

建議做法（仍以 iOS extension 限制為前提）：

- 優先用 popup 內的 in-memory state（不依賴持久儲存）
- 若一定要保存設定，再評估 Safari extension 的 `storage`/IndexedDB 在目標裝置上的可靠性與容量限制
