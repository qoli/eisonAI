# 原始庫（Raw Library）：以 JSON 檔保存每次輸入/輸出

你目前的決策是：

- **不設計 cache/優化庫**（例如 embedding / FTS / 各種索引）——先不做。
- 「原始庫」就是 **一筆資料一個 JSON 檔**，完整保存：
  - 網頁原文（或 Readability 後正文）
  - 總結結果
  - 日期與必要 metadata

這種做法非常適合 MVP：可靠、好 debug、也不需要先定 schema/migration。

---

## 1) 為什麼放在 App Group？

- Safari extension（`SafariWebExtensionHandler`）和主 App 是不同 sandbox。
- 唯一能共用檔案的地方就是 **App Group container**。

你目前的 App Group：`group.com.qoli.eisonAI`（已在 entitlements 使用）。

---

## 2) 建議的資料夾結構（Raw Library）

在 App Group container 下建立：

```
AppGroup/
  RawLibrary/
    Items/        # 一筆一檔（JSON）
    Trash/        #（可選）主 App 刪除時先搬到這裡，方便復原/排查
  Cache/          #（可選）未來優化庫/衍生快取再加
```

說明：

- extension 只要能寫 `RawLibrary/Items/` 就足夠。
- 主 App 負責讀取/排序/顯示，也可以負責刪除與匯出。

---

## 3) 檔名策略（URL 去重 + 排序友善）

你目前決策是：

- **同一個 URL 只保留最後一筆**
- **最多保留 200 筆**
- 檔名用：`<URL_HASH>__<UTC時間戳>.json`

例如（示意）：

`<sha256(url)>__20251217T123456789Z.json`

重點：

- URL hash 讓你可以在寫入時「先刪掉同 hash 前綴的舊檔」→ 達成同 URL 只保留最後一筆
- timestamp 讓檔案可排序（也方便做全局 200 筆的淘汰）
- 避免在檔名放 `:` 等跨平台不穩字元（此格式不含冒號）

---

## 4) JSON 結構建議（版本化 + 可擴充）

建議最少欄位：

- `v`：schema 版本（先固定 `1`）
- `id`：UUID（同時寫進檔名與 JSON，方便去重/索引）
- `createdAt`：ISO8601（UTC）
- `url` / `title`
- `articleText`：Readability 後正文（或你決定的原文）
- `summaryText`：WebLLM 產出的摘要

建議可選欄位（未來用得到就加，不需要一次做完）：

- `systemPrompt` / `userPrompt`
- `modelId` / `wasm` / `webllmVersion`
- `pageHTML`（通常不建議，太大；真的需要再加）
- `tokenEstimate` / `durationMs`

> 你只要保留 `v`，未來要「從 Raw Library 建 cache 庫」或做格式升級就不會卡死。

---

## 5) Extension 寫入方式（native handler：原子寫檔）

流程概念：

1. `popup.js` 生成完摘要後 → `browser.runtime.sendNativeMessage({ command: "saveRawItem", payload: {...} })`
2. `SafariWebExtensionHandler` 收到 → 組出 `RawItem` JSON（補 `id/createdAt/v`）
3. 寫到 App Group `RawLibrary/Items/`（用 `.atomic`）
4. 回傳 `{ ok: true, id }` 給 JS

注意：

- handler 內只做「組 JSON + 寫檔」即可，避免做重計算。
- `articleText` 可能很長：依目前設計 Raw Library **不截斷原文**。

---

## 6) 主 App 讀取方式（列舉目錄 + 解析 JSON）

MVP 最簡單做法：

- `FileManager.contentsOfDirectory` 列出 `RawLibrary/Items/`
- 依檔名排序（或讀 JSON 的 `createdAt`）
- 逐檔 decode 顯示（大量資料時再做 lazy/load-on-demand）

未來若檔案數上千造成效能問題，再考慮：

- 主 App 生成一份 `index.json`（只含 `id/createdAt/title/url`）加速列表
- 或導入「cache/優化庫」（例如 sqlite-data）做索引/搜尋/embedding

---

## 7) 與 sqlite-data / TracklyReborn 的關係（先記著）

你已經把 `sqlite-data` 加到主 App target，未來若你要做「優化庫」：

- 參考 TracklyReborn 的模式：`DatabasePool` + `busyMode = .timeout(2~5)` + migrator
- 讓 sqlite-data 只處理「可重建」的衍生資料（embedding/FTS/索引），Raw Library 仍是 source of truth

---

## 8) Debug：如何看 native 的 os_log（macOS / iOS）

### macOS（My Mac / Designed for iPad）

- **Console.app**：在搜尋框輸入 `subsystem:com.qoli.eisonAI`，可再加 `category:RawLibrary` / `category:Native`
- **Terminal**（注意用 `/usr/bin/log`）：
  - 即時串流：`/usr/bin/log stream --style syslog --level info --predicate 'subsystem == "com.qoli.eisonAI"'`
  - 只看 RawLibrary：`/usr/bin/log stream --style syslog --level debug --predicate 'subsystem == "com.qoli.eisonAI" && category == "RawLibrary"'`
  - 看最近 10 分鐘：`/usr/bin/log show --last 10m --style syslog --predicate 'subsystem == "com.qoli.eisonAI"'`

### iOS（真機/模擬器）

- Xcode → `Window` → `Devices and Simulators` → 選裝置 → `Open Console`
- 或 macOS `Console.app` 選對應裝置再過濾 `subsystem`

### 不依賴 OSLog 的檢查法（建議先看這個）

- `popup.js` 成功儲存會 `console.log("Saved raw history item", resp)`，其中包含 `directoryPath` / `savedPath`，用這個路徑去確認檔案實際寫到哪裡。
