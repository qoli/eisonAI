# EisonAI

EisonAI 是一個智能的 Safari 瀏覽器插件，使用先進的大語言模型（LLM）技術來自動總結網頁內容。它能夠智能提取網頁的主要內容，並生成精確的摘要，幫助用戶快速理解網頁要點。

## 功能特點

- **智能內容提取**：使用 [Readability.js](https://github.com/mozilla/readability) 技術自動識別和提取網頁的主要內容，去除廣告和無關元素。
- **AI 智能總結**：整合大語言模型（LLM）生成網頁內容的精確摘要。
    - 支援 OpenAI 相容的 API。
    - 支援 Google Gemini API。
- **互動式對話**：支持與 AI 進行多輪對話，深入探討網頁內容。
- **優雅的界面**：
    - 迷你浮動按鈕，不影響網頁瀏覽。
    - 簡潔的對話框設計。
    - 支持系統明暗主題自適應。
    - 打字機效果的訊息顯示。
    - 響應式 UI 設計，自動適應 macOS 和 iOS 平台。
- **靈活的顯示模式**：
    - 迷你圖標模式：在頁面角落顯示小圖標。
    - 隱藏模式：完全隱藏，通過快捷鍵喚出。
- **進階功能**：
  - 支援 API 連線測試。
  - 自訂系統提示詞 (System Prompt)。
  - 摘要結果本地快取，避免重複生成。
  - 支援鍵盤快捷操作（Enter 發送）。
  - 支援將摘要結果分享到其他應用程式。

![EisonAI 使用界面](assets/images/SCR-20250227-ghmf.jpeg)

## 系統架構

### 核心模組

1. **Content Script (`content.js`)**
   - **職責**：被注入到每個網頁中。
   - **核心功能**：監聽來自背景腳本的指令，使用 `Readability.js` 解析當前頁面的 DOM，提取主要文章內容，並將結果回傳。

2. **Background Script (`background.js`)**
   - **職責**：作為擴展功能的核心事件協調者。
   - **核心功能**：建立一個持久的訊息通道，負責在 Popup 彈出視窗和 Content Script 之間轉發請求和響應，實現兩者之間的解耦。

3. **彈出視窗 (Popup - `popup.js`)**
   - **職責**：提供主要的使用者互動介面。
   - **核心功能**：
     - 觸發內容總結流程。
     - 與使用者設定的 LLM API (如 OpenAI, Gemini) 進行通訊。
     - 顯示總結結果和對話歷史。
     - 檢查 API 連線狀態並提供即時反饋。
     - 提供重新生成摘要、開啟設定頁面等操作。
     - 支援分享摘要結果。
     - 若無快取，開啟時自動觸發摘要流程。

4. **設置頁面 (Settings - `settings.js`)**
   - **職責**：管理所有使用者可配置的選項。
   - **核心功能**：
     - 設定 API 的 URL、金鑰 (Key) 和模型 (Model)。
     - 提供 API 連線測試功能。
     - 自訂用於生成摘要的系統提示詞 (System Prompt) 和使用者提示詞 (User Prompt)。
     - 選擇擴展的顯示模式（迷你圖標或隱藏）。
     - 所有設定都安全地儲存在本地。

### 技術特點

- **非同步訊息傳遞架構**：使用 `browser.runtime.onMessage` 在 Popup、Background 和 Content Script 之間進行高效的非同步通訊。
- **內容提取**：使用 [Readability.js](https://github.com/mozilla/readability) 進行精準的網頁正文解析。
- **模組化設計**：將功能清晰地劃分到獨立的腳本中（內容提取、UI 互動、API 設定、背景通訊），易於維護和擴展。
- **本地持久化存儲**：使用 `browser.storage.local` 安全地儲存使用者 API 設定和應用程式狀態。
- **跨平台 UI 適應**：通過 JavaScript 動態檢測運行環境（macOS/iOS），並應用相應的 CSS 樣式，提供一致的用戶體驗。
- **安全性**：遵循瀏覽器擴展的內容安全策略（CSP），並要求 API 使用 HTTPS 連線。

## 系統要求

- macOS 12.0 或更高版本（用於 macOS Safari 插件）
- iOS 15.0 或更高版本（用於 iOS Safari 插件）
- Safari 15.0 或更高版本

## 安裝方法

1. 從 testflight 下載 EisonAI https://testflight.apple.com/join/1nfTzlPS
2. 在 Safari 設定中啟用 EisonAI 插件：
   - 打開 Safari 偏好設定
   - 點擊「擴展」標籤
   - 勾選 EisonAI 插件

## 使用方法

1. **開啟總結**：
   - 點擊瀏覽器右下角的 EisonAI 圖標
   - 或使用配置的快捷鍵

2. **查看摘要**：
   - 插件會自動提取頁面內容
   - 使用 AI 生成內容摘要
   - 顯示網頁標題和來源信息

3. **深入對話**：
   - 在對話框中輸入問題
   - 按 Enter 發送
   - 與 AI 進行多輪對話，深入探討內容

4. **重新生成**：
   - 如果對摘要不滿意，可以點擊 "Reanswer" 重新生成
   - 系統會重新分析網頁內容並生成新的摘要

## 開發指南

### 環境設置

1. 克隆倉庫：
```bash
git clone https://github.com/yourusername/eisonAI.git
cd eisonAI
```

2. 安裝依賴：
```bash
bundle install
```

3. 開啟 Xcode 項目：
```bash
open eisonAI.xcodeproj
```

### 核心依賴

- browser API
- Readability.js
- contentGPT.js
- popup.css

### 開發注意事項

1. API 設置相關：
   - 必須使用 HTTPS
   - URL 需符合特定格式 (https://example.com/v1)
   - 必須進行 API 驗證測試

2. 程式碼規範：
   - 使用模組化設計
   - 實作適當的錯誤處理
   - 注意跨平台兼容性
   - 遵循 CSP 安全準則

## 貢獻指南

歡迎貢獻！請查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解如何參與項目開發。

## 行為準則

本項目遵循 [行為準則](CODE_OF_CONDUCT.md)，請所有參與者遵守。

## 關聯項目

### [newSafari](https://github.com/qoli/newSafari)

newSafari 是一個相似的 Safari 網頁內容擷取與總結工具，提供以下特點：

- **基本擷取模式**：
  - 自動獲取當前 Safari 頁面的 URL 和標題
  - 智能清理 HTML 內容，提取純文本
  - 使用 LLM 處理頁面內容
  - 自動保存為 Markdown 文件
  - 支援一鍵複製到剪貼板

- **互動式總結模式**：
  - 自動提取網頁主要內容
  - 生成結構化摘要
  - 支援互動式問答
  - 支援流式輸出
  - 智能對話記憶上下文

兩個專案都致力於提升 Safari 瀏覽器的閱讀體驗，但採用不同的技術實現方案：
- EisonAI 使用瀏覽器擴展形式，直接整合進 Safari
- newSafari 採用獨立應用程式方式，通過 Python 實現

## 許可證

本項目基於 MIT 許可證開源 - 查看 [LICENSE](LICENSE) 文件了解更多信息。
## 更新紀錄

### v1.0.0 (2025-07-25)

- ✨ feat(popup): 開啟時自動觸發摘要
  - 若無現有摘要，彈窗開啟時會自動開始總結
  - 改善使用者體驗，無需手動點擊
- ⚡️ perf(popup): 降低初始載入延遲
- ✨ feat(popup): 新增分享摘要功能
  - 使用 Web Share API 將標題、摘要和原始網址分享出去