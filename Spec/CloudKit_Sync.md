# Spec：RawLibrary CloudKit 同步（iOS 主 App）

## 背景

RawLibrary 目前以 App Group 本地 JSON 檔案為主（`RawLibrary/Items/*.json`、`RawLibrary/FavoriteItems/*.json`、`RawLibrary/Favorite.json`）。
目標是把 RawLibrary 在多裝置間同步，且不依賴 iCloud Drive（避免 `.download`、File Provider 行為造成開發難題），改用 **CloudKit 私有資料庫 + 自訂 Zone**。

## 目標（to-be）

- RawLibrary 的 JSON 檔案 **跨裝置同步**（私人 iCloud）。
- 同步邏輯可控、可重試、可支援「本機覆蓋遠端」。
- **Last Write Wins**（以時間戳決定優先）。
- 不改變現有 RawLibrary 檔案格式。

## 非目標（non-goals）

- 不使用 iCloud Drive / File Provider。
- 不做結構化資料庫遷移（只同步檔案）。
- 不做多人共享（僅私有 DB）。

## 需求範圍

同步目標（App Group 容器內）：
- `RawLibrary/Items/*.json`
- `RawLibrary/FavoriteItems/*.json`
- `RawLibrary/Favorite.json`

## CloudKit 資料模型

- **Database**：Private DB
- **Zone**：`RawLibraryZone`
- **Record Type**：`RawLibraryFile`
- **Fields（最小化）**
  - `filename` (String)
  - `path` (String)  // e.g. `Items/xxx.json`, `FavoriteItems/xxx.json`, `Favorite.json`
  - `filedata` (Asset or Bytes)

> 註：為了確保結構變動仍可同步，只保存檔案與路徑，不依賴 JSON schema。

### Record ID 規則

- `recordName = sha256(path)`
- 同一路徑只會對應單一 record（避免重覆）

## 本機資料結構

- App Group 容器：`group.com.qoli.eisonAI`
- RawLibrary root：`RawLibrary/`
- Manifest（同步索引）：`RawLibrary/sync_manifest.json`

## 同步策略

### Pull（CloudKit → 本機）

- 使用 `CKFetchRecordZoneChangesOperation` 以 change token 增量拉取。
- 對每筆變更：
  - 下載 `filedata` 覆蓋本機檔案（必要時建立資料夾）。
  - 設置本機檔案 `modificationDate = record.modificationDate`。
- 對每筆刪除：
  - 刪本機對應檔案。

### Push（本機 → CloudKit）

- 掃描本機檔案清單。
- 與 manifest 的 `lastLocalModifiedAt` / `lastKnownServerModifiedAt` 比對。
- 本機較新 → 上傳 `filedata`。
- 本機刪除 → 發送 record delete。

### 衝突策略（Last Write Wins）

- 以 **本機檔案 modificationDate** 與 **CKRecord.modificationDate** 比較。
- 若遇 `serverRecordChanged`：
  - 若本機較新 → 以 server record 重送覆蓋。
  - 若 server 較新 → 覆蓋本機。

## Manifest（同步索引）

位置：`RawLibrary/sync_manifest.json`

建議格式：
```json
{
  "v": 1,
  "updatedAt": "2025-12-21T00:00:00Z",
  "changeTokenData": "...",
  "files": {
    "Items/abc.json": {
      "path": "Items/abc.json",
      "recordName": "<sha256>",
      "lastLocalModifiedAt": "...",
      "lastKnownServerModifiedAt": "..."
    }
  }
}
```

用途：
- 減少不必要的重複上傳。
- 記錄最後一次 server 時間，用於 LWW 判斷。
- 判斷「本機刪除 → 遠端刪除」。

## 「本機覆蓋遠端」功能

需求：設定頁面提供一鍵功能，將 **本機資料完整覆蓋遠端**。

流程：
1) 取得 CloudKit `RawLibraryFile` 全量列表（Zone query）。
2) 比對本機檔案清單：
   - 遠端有、本機沒有 → delete record。
   - 本機有 → 上傳本機版本（強制覆蓋）。

注意：
- 若使用 `path BEGINSWITH` 查詢，需在 schema 中將 `path` 設為 Searchable。
- 若使用全量 query，則不需 index，但可能較慢。

## 觸發點

- App 進入前景
- RawLibrary 寫入/刪除/收藏變更
- 手動「覆蓋遠端」

## 錯誤處理與重試

- CloudKit `requestRateLimited` / `zoneBusy`：依 `retryAfterSeconds` 重試。
- `accountTemporarilyUnavailable` / `notAuthenticated`：提示使用者登入 iCloud。
- 失敗時不破壞本機資料，延後重試。

## 安全與容量

- Private DB，僅使用者本人可讀寫。
- CloudKit 單筆 record 若資料過大需改走 `CKAsset`。
- RawLibrary 有 200 筆限制，必要時同步後裁剪本機（避免爆量）。

## 測試與驗證

1) A 裝置新增 RawLibrary → B 裝置拉取成功。
2) A 裝置刪除 → B 裝置刪除同步。
3) A/B 同時修改同檔 → 以時間戳決定勝者。
4) 「本機覆蓋遠端」後，遠端只剩本機檔案。

## 需要的權限 / 能力

- App target 啟用 `iCloud` + `CloudKit`。
- Entitlements 包含 `iCloud.com.qoli.eisonAI`。
- CloudKit Dashboard 建立 `RawLibraryFile` record type 與必要索引。

