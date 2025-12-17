# Safari Extension 持久化資料：App Group Queue（主 App 用 SQLiteData 寫入）

你已經把 `pointfreeco/sqlite-data` 加到「主 App target」後，下一個問題通常會變成：

- Safari extension（`popup.js` → `SafariWebExtensionHandler`）產生的內容，要怎麼落盤？
- 我們能不能「喚醒主 App」來做 DB 的讀寫？

這份文件整理一個在 iOS 上比較務實、可控的方案：**extension 只負責把資料寫到 App Group 的 queue（JSON 檔），主 App 有機會時再把 queue 消化進 SQLiteData/GRDB**。

---

## 0) 先釐清：extension 為何不能直接用主 App 的 DB？

- `SafariWebExtensionHandler` 是 **Extension target** 的程式碼，和主 App 是不同的 binary / sandbox。
- Extension **不能**存取主 App 的 container（`Documents/Library` 等），只能存取：
  - 自己的 container
  - **App Group container**（主 App + extension 共用）
- 因此：
  - 要讓 extension **直接寫入 SQLite**：DB 檔必須放在 App Group，且 extension target 也要能 `import SQLiteData/GRDB`。
  - 如果你不想把 `sqlite-data` 加進 extension（你目前就是這個狀態）：就要走 **App Group queue**（本文件主軸）。

---

## 1) 為什麼「用 App Intents 喚醒主 App」不太可行？

在 iOS 上，App Intents 比較像「系統觸發你的 app/extension 來執行一段工作」，而不是「extension 能可靠地把主 App 拉起來當成 RPC server」。

實務限制通常是：

- Safari extension 端沒有一個穩定、可同步回傳結果的方式，去「要求系統立刻執行某個 App Intent」。
- 就算 intent 有被執行，也不保證會在「主 App UI process」跑，時機也不可控。
- 因此 intent 很難滿足「extension 需要立即讀/寫 DB 並拿到回應」這種 IPC 需求。

所以我們退一步：**extension 先把資料可靠落盤到 App Group**，主 App 之後再處理。

---

## 2) 方案概覽：兩條路（你現在選 B）

### A. Extension 直寫 SQLite（同步、立即）

- 需要把 `sqlite-data`（或至少 `GRDB`）加入 Extension target
- DB 檔放 App Group，且 App/Extension 共用同一套 migration

### B. App Group queue（JSON 檔）→ 主 App 用 SQLiteData 落庫（非同步、最輕）

- Extension 只做：把「要寫入的事件」寫成 JSON 檔到 App Group
- 主 App 只要有機會（啟動、回前景、背景任務），就把 queue 消化進 DB

你目前的目標（extension 不引入 sqlite-data）就是 **B**。

---

## 3) App Group Queue 設計（推薦：一個事件一個檔案）

你的 App Group 是：`group.com.qoli.eisonAI`（已用於 `UserDefaults(suiteName:)`）。

建議在 App Group container 下建立這種結構（示意）：

```
AppGroup/
  Queue/
    Inbox/        # extension 只寫這裡
    Processing/   # 主 app 搬移過來表示「已認領」
    Failed/       # 寫 DB 失敗的 event
  Cache/
    summaries.json  #（可選）主 app 輸出給 extension 讀的快取
  Database/
    eison.sqlite    #（可選）若你也想把 DB 放 App Group
```

### 3.1 為什麼「一個事件一個檔」？

- 避免多進程同時 append 同一個檔案導致損毀/競爭
- 檔案寫入可以用 `.atomic`，成功率高
- 主 App 可以用「搬移檔案」當作鎖（move to Processing 表示已認領）

### 3.2 事件格式（JSON）

最簡單可用的 envelope（建議 `Codable`）：

```json
{
  "v": 1,
  "id": "UUID",
  "createdAt": "ISO8601",
  "type": "saveSummary",
  "payload": { "...": "..." }
}
```

`payload` 依事件類型決定，例如 `saveSummary`：

```json
{
  "url": "https://...",
  "title": "…",
  "summary": "…",
  "model": "Qwen3-0.6B…"
}
```

### 3.3 檔名策略（排序 + 去重）

檔名建議帶時間 + UUID，方便排序與 debug，例如：

`2025-12-17T12-34-56Z__<UUID>.json`

另外，`id` 字段用來做主 App 端的 **idempotency**（避免重複插入）。

---

## 4) Extension 端：只做 enqueue（快速回應）

extension 端（`SafariWebExtensionHandler`）只需要：

1. 解析 JS message（例如 `command: "enqueue"` / `command: "saveSummary"`）
2. 把 payload 包成 envelope JSON
3. 寫入 App Group `Queue/Inbox/`（`.atomic`）
4. 立刻回傳 `{ ok: true, id }`

> 重點：不要在 handler 做重工作（例如 migration/DB 寫入/大檔處理），避免 extension 超時或被系統殺掉。

---

## 5) 主 App：消化 queue → 寫入 SQLiteData（參考 TracklyReborn 的做法）

這邊才是 sqlite-data/GRDB 的主要舞台。

### 5.1 DB 初始化建議（TracklyReborn 的經驗點）

- 用 `DatabasePool` 當 live database（並發比較友善）
- 設定 `busyMode = .timeout(2~5)`，降低 `SQLITE_BUSY`
- `foreignKeysEnabled = true`
-（可選）在 app 進入背景時做 `wal_checkpoint(PASSIVE)`，避免 WAL 長太大

你可以直接參考 `TracklyReborn/Services/Database/AppDatabase.swift` 的配置方式（busy timeout / DatabasePool / migrator）。

### 5.2 queue 消費的「claim 模式」（避免重複處理）

主 App 端建議這樣做（概念）：

1. 列出 `Queue/Inbox` 的檔案（依檔名時間排序）
2. 對每個檔案先 `move` 到 `Queue/Processing`（move 成功 = 認領成功）
3. decode JSON → 寫入 DB（`database.write { ... }`）
4. 成功：刪掉 `Processing` 檔案
5. 失敗：把檔案 move 到 `Queue/Failed`，並可附加一個 `.error.txt`

### 5.3 主 App 什麼時候跑 queue？

MVP 建議先做「可預期」的時機：

- App 啟動後（SwiftUI `.task`）
- App 回到前景（`scenePhase == .active`）

進階（可選）：

- `BGAppRefreshTask` / `BGProcessingTask`（不保證即時，但能提高自動消化機率）

---

## 6) Extension 若需要「讀」怎麼辦？

如果你堅持「extension 不碰 DB」，那 extension 的讀取只能來自 App Group 的「快取檔」，而不是直接 query SQLite。

常見做法：

- 主 App 消化 queue 並寫 DB 後，同步更新一份 `Cache/summaries.json`
- extension 需要顯示歷史時，就讀這份 JSON（可接受資料稍微延遲）

---

## 7) 下一步（落地順序）

1. 先定義你要 enqueue 的第一個事件（建議從 `saveSummary` 開始）
2. 在 `SafariWebExtensionHandler` 加一個 `enqueue`/`saveSummary` 命令：寫 JSON 檔到 `Queue/Inbox`
3. 在主 App 加一個 `QueueProcessor`：啟動/回前景時掃描 `Queue/Inbox` → 寫 DB
4. DB schema（`summary` 表）與 migration（參考 TracklyReborn 的 `AppDatabase.swift` 模式）
5.（可選）做 `Cache/summaries.json`，讓 extension 也能讀到「最新 N 筆」
