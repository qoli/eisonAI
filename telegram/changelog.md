## 2.12

### 新增
- 新增「結果翻譯」設定開關，預設關閉。啟用後，eisonAI 會將生成結果翻譯成所選語言，並保留原文與譯文以供切換查看。

### 修正
- App 與 Safari Extension 的生成路徑統一為 Apple Intelligence 或 BYOK。Auto 可在 Apple Intelligence 不可用時選用 BYOK；明確選擇 Apple Intelligence 時則會停止並顯示錯誤，不會靜默將內容送往外部服務。

### 移除
- 移除可下載的 MLX 本地模型、模型目錄、模型管理介面與背景下載流程。
