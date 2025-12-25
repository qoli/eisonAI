# OpenDocs — EisonAI（技術難點與特點）

本文件聚焦在 EisonAI 的技術難點、設計取捨與關鍵實作細節，協助開發者理解為何專案要這樣做、該注意哪些「坑」，以及改動時的風險點。

## 文件結構（導覽）

- 技術特點：這個專案為何「不尋常」
- 技術難點與取捨：核心限制與設計選擇
- 模組與責任：各子系統做什麼
- 近 2 週熱區：反覆改動代表的真實痛點
- 風險點與排障：最容易壞與最快定位的方法

## 技術特點（Why it’s interesting）

- **Safari Extension 內本機推理**：在 popup 內用 WebLLM（WebGPU + WebWorker）跑本地模型，避免雲端 API。
- **Bundled assets 策略**：模型與 wasm 隨 extension bundle 打包，避免 iOS extension runtime 下載與持久儲存限制。
- **Safari 特化修補**：`webllm.js` vendor 檔需保留 `safari-web-extension://` 兼容 patch，避免 Cache API/Request URL 錯誤。
- **內容擷取與推理解耦**：Readability 只在 content script，推理只在 popup，降低 extension 生命週期不穩定因素。

## 主要技術難點與取捨

### 1) Safari Extension 限制（存取 / 生命週期 / 背景執行）
- popup 是最穩定的推理入口；**不使用 background/service worker**，避免 Safari 在 iOS 的限制與不確定性。
- **不使用 native messaging 做推理**（`SafariWebExtensionHandler` 僅做設定讀取），避免算力/資源配置不足與不穩定。

### 2) WebGPU 在 iOS Safari 的不確定性
- 需要 **真機** 驗證；模擬器無法代表真實 WebGPU 表現。
- 若裝置或 Safari 不支援，popup 會無法載入模型，需要在 UI 提示與錯誤處理上特別留意。

### 3) 模型/wasm 資產管理（Bundled Assets）
- iOS extension **不可靠的 runtime 下載** 與持久儲存行為，促使採用 bundled assets。
- `Shared (Extension)/Resources/webllm-assets/` 為 **gitignored**，每位開發者需自行下載並保持結構一致。

### 4) CSP 與 wasm / worker 限制
- Safari extension CSP 需允許 `wasm-unsafe-eval` 與 `worker-src`，否則 wasm 或 worker 無法啟動。
- CSP 變動風險高（常造成隱性錯誤），改動 `manifest.json` 需特別驗證。

### 5) `safari-web-extension://` 相容性問題
- Safari 對非 http(s) URL 的 Cache API / `new Request(url)` 存在限制。
- 需保留 `webllm.js` 的 Safari patch；更新 WebLLM runtime 時 **最容易被誤刪**。

### 6) 長文摘要的 Token/記憶體壓力
- 目前以 **字元截斷** 控制 prompt 大小；品質 vs.穩定性取捨。
- 若要提升品質，需實作 chunk + reduce（分段摘要 + 合併摘要）。

## 模組與責任區（系統性視角）

### A) Extension 端推理與 UI
- popup 進入點：`Shared (Extension)/Resources/webllm/popup.html`
- 推理流程與狀態機：`Shared (Extension)/Resources/webllm/popup.js`
- WebWorker：`Shared (Extension)/Resources/webllm/worker.js`
- WebLLM runtime（含 Safari patch）：`Shared (Extension)/Resources/webllm/webllm.js`

### B) Extension 端內容擷取
- Readability 與頁面正文：`Shared (Extension)/Resources/contentReadability.js` + `Shared (Extension)/Resources/content.js`

### C) 原生橋接與設定同步
- Native bridge：`Shared (Extension)/SafariWebExtensionHandler.swift`
- App 端設定：`iOS (App)/Shared/Config/AppConfig.swift`

### D) App 端長文與 token 計算
- Token 估算與分段：`iOS (App)/Features/Clipboard/ClipboardKeyPointViewModel.swift`
- 相關規格：`Spec/LONG_DOCUMENT_READING_PIPELINE.md`、`Spec/Updatetokenizer.md`、`Docs/key-point-function-chains.md`

### E) 模型與資產
- 下載腳本：`Scripts/download_webllm_assets.py`
- 本地資產位置：`Shared (Extension)/Resources/webllm-assets/`

## 關鍵檔案與責任區（快速索引）

- 內容擷取：`Shared (Extension)/Resources/contentReadability.js` + `Shared (Extension)/Resources/content.js`
- popup UI：`Shared (Extension)/Resources/webllm/popup.html`
- popup 邏輯：`Shared (Extension)/Resources/webllm/popup.js`
- WebWorker 入口：`Shared (Extension)/Resources/webllm/worker.js`
- WebLLM runtime（vendor + Safari patch）：`Shared (Extension)/Resources/webllm/webllm.js`
- Extension CSP / entry：`Shared (Extension)/Resources/manifest.json`
- 下載 assets 腳本：`Scripts/download_webllm_assets.py`

## 最近 2 週的熱區（2025-12-11 → 2025-12-25）

以下是近 2 週提交中**反覆修改**的檔案與對應的技術難點。這些區域通常是最容易出問題、也最值得優先理解的部分。

### 1) Extension 推理與狀態機（頻繁變更）
- 主要檔案：`Shared (Extension)/Resources/webllm/popup.js`、`Shared (Extension)/Resources/background.js`、`Shared (Extension)/Resources/content.js`
- 技術難點：popup/background/content 三方狀態同步、快取結果優先序、錯誤訊息覆蓋、以及 Safari 的生命週期不穩定導致的競態條件。

### 2) UI 與推理流程耦合（可視化與串流）
- 主要檔案：`Shared (Extension)/Resources/webllm/popup.html`、`Shared (Extension)/Resources/webllm/popup.css`
- 技術難點：長文流程的可視化、串流摘要呈現、與狀態訊息一致性；UI 常需跟著流程邏輯同步調整。

### 3) 長文處理與 token 計算一致性（App/Extension 兩端）
- 主要檔案：`iOS (App)/Features/Clipboard/ClipboardKeyPointViewModel.swift`、`Spec/LONG_DOCUMENT_READING_PIPELINE.md`、`Spec/Updatetokenizer.md`、`Docs/key-point-function-chains.md`
- 技術難點：tokenizer 換代與 fallback、動態分段策略、App 與 Extension 算法一致性，以及 token 上限與品質的平衡。

### 4) Native ↔︎ Extension 橋接與設定同步
- 主要檔案：`Shared (Extension)/SafariWebExtensionHandler.swift`、`iOS (App)/Shared/Config/AppConfig.swift`
- 技術難點：原生設定的同步與版本相容、App Group 資料一致性、以及 Swift/JS 之間的協定穩定性。

### 5) SwiftUI 導航與資料流（Library / Settings）
- 主要檔案：`iOS (App)/Features/Library/LibraryRootView.swift`、`iOS (App)/Features/Library/LibraryItemDetailView.swift`、`iOS (App)/Features/Settings/SettingsView.swift`
- 技術難點：深層連結導航、狀態來源分散、與資料更新（例如標籤/快取）同步時序。

### 6) 近期變更軌跡（依 git 提交）

這一段用「提交時間軸」來描述**實際反覆調整的技術點**，便於快速理解「改了什麼、為什麼難」。日期皆為 2025 年。

#### 6.1 Token 計算辦法（3 次變化）

在 12/24～12/25 之間，token 計算方式出現連續三次調整，代表這裡是核心難點之一：

- **12/24 — a0c035a**：更換 tokenizer 計算器，移除舊的 GPTEncoder，改用新的 tokenizer 流程並調整 Extension/App 端的估算邏輯。
- **12/24 — 20668fb**：App 端改採 SwiftikToken，重構 `GPTTokenEstimator`，並調整分段計算邏輯（例如透過二分搜尋找切點）。
- **12/25 — 17e0bab**：tokenizer base 從 `o200k_base` 轉為 `p50k_base`，Extension 與 App 同步更新。

補充（同類風險點）：
- **12/25 — b54ea79**：長文分段策略改為動態分段（最多 5 段），這會直接影響 token 估算與推理穩定性。
- **12/25 — 393865d**（文件）：補充 tokenizer fallback 說明，反映「tokenizer 不可用時需降級」的實務情況。

#### 6.2 Extension 狀態機與串流（同日多次修正）

12/13 當天有一串連續提交，集中在**狀態同步與競態處理**，這是 Safari Extension 的高風險區：

- **42d572f**：新增摘要串流顯示（背景 → popup 即時推送）。
- **75bc716**：補強背景狀態管理與快取流程（URL 綁定與重置）。
- **9ccc4c4**：新增 summaryStatusUpdate 處理，解決快取與錯誤狀態覆寫順序問題。
- **c3883a6**：加入逾時與狀態重置邏輯，避免殭屍狀態。
- **5068b64**：修正 summaryComplete 處理與快取流程，避免「完成後狀態錯亂」。
- **4300a8e / 49a6e51**：調整 popup 狀態顯示與修正完成後顯示錯誤。

這一串改動反映的技術難點是：**popup/background/content 之間的生命週期不一致**，極易觸發競態、狀態回退或錯誤訊息覆蓋。

## 風險點（改動時容易壞的地方）

- **更新 WebLLM vendor**：忘記帶回 Safari patch 會導致載入錯誤。
- **調整 CSP**：錯一個字就可能讓 wasm/worker 無法啟動。
- **調整模型/wasm 路徑**：資產目錄結構若與 `popup.js` 不一致就會 404。
- **推理入口移動**：若從 popup 移出，需重新處理 Safari 的生命週期與權限限制。

## 常見排障關鍵字

- `WebGPU unavailable`
- `Refused to create a WebAssembly object... 'unsafe-eval'/'wasm-unsafe-eval'`
- `Request url is not HTTP/HTTPS`
- `fetch fail` / `404`（多半是 assets 路徑或缺檔）

## 延伸閱讀

- 開發與排障：`Docs/DEVELOPMENT.md`
- 內容擷取：`Docs/content.js.md`
- popup 介紹：`Docs/popup.md`
- 設定頁面：`Docs/settings.md`
