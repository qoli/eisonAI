# Xcode 自動化腳本

本專案提供兩支以 AppleScript 為基礎的 Xcode 輔助腳本，放在 `Scripts/`：

- `Scripts/run_xcode.sh`：打開指定的 Xcode project/workspace，並對 Xcode 送出 `Cmd-R`
- `Scripts/export_xcode_console.sh`：聚焦 Xcode debug console，將目前 console 內容輸出到 `logs/xcode/<timestamp>.log`

這兩支腳本都依賴 macOS 的 UI scripting，因此不是直接呼叫 `xcodebuild`，而是透過 `osascript` + `System Events` 操作 Xcode 前景視窗。

## 前提條件

- macOS 已安裝 `/Applications/Xcode.app`
- 執行腳本的程式具有「輔助使用」權限
  - 例如 `Terminal`、`iTerm`、`Script Editor`、或你實際執行腳本的宿主程式
- Xcode 已能正常開啟這個專案

若未授權「輔助使用」，`System Events` 會無法操作 Xcode，腳本將失敗。

## `Scripts/run_xcode.sh`

用途：
- 打開 `eisonAI.xcodeproj`
- 等待指定秒數
- 對 Xcode 送出 `Cmd-R`

最常用的執行方式：

```bash
Scripts/run_xcode.sh
```

常見變體：

```bash
Scripts/run_xcode.sh --wait 1
Scripts/run_xcode.sh --open-only
Scripts/run_xcode.sh --path /path/to/App.xcworkspace
```

參數：

- `--path PATH`
  - 指定要打開的 `.xcodeproj` 或 `.xcworkspace`
  - 預設為 repo 內的 `eisonAI.xcodeproj`
- `--wait SECONDS`
  - 打開或切換到 Xcode 後，送出 `Cmd-R` 前的等待秒數
  - 預設 `3`
- `--open-only`
  - 只打開 Xcode 與專案，不送出 `Cmd-R`

適用情境：

- 想從 shell 快速切回 Xcode 並直接執行目前 scheme
- 需要做可重複的本地開發動作，但不想手動切視窗按 `Run`

限制：

- 腳本不會幫你切換 scheme 或 destination
- 實際執行的是 Xcode 當下選中的 scheme / destination
- 若 Xcode 當前狀態跳出警告、簽名視窗、或其他 modal，`Cmd-R` 可能不會落在預期位置

## `Scripts/export_xcode_console.sh`

用途：
- 將 Xcode 切到前景
- 顯示 `Debug Area`
- 聚焦 debug console
- 讀取 console 文字內容
- 輸出到 `logs/xcode/<timestamp>.log`

最常用的執行方式：

```bash
Scripts/export_xcode_console.sh
```

常見變體：

```bash
Scripts/export_xcode_console.sh --wait 1
Scripts/export_xcode_console.sh --project /path/to/App.xcodeproj
Scripts/export_xcode_console.sh --output-dir /tmp/xcode-logs
```

參數：

- `--output-dir PATH`
  - 匯出檔案目錄
  - 預設為 repo 內的 `logs/xcode`
- `--project PATH`
  - 若 Xcode 尚未開啟，可先打開指定的 `.xcodeproj` 或 `.xcworkspace`
  - 預設會使用 `eisonAI.xcodeproj`
- `--wait SECONDS`
  - 開啟或聚焦 Xcode 後的等待秒數
  - 預設 `0.5`

輸出格式：

- 檔名使用時間戳：`YYYYMMDD-HHMMSS.log`
- 例如：`logs/xcode/20260419-024055.log`

適用情境：

- 保留這次 run 的 Xcode console 輸出
- 需要把 Xcode console 日誌交給其他腳本或後續分析流程
- 在不切去 `Devices and Simulators`、`Console.app`、`xcodebuild` 的前提下，直接取出目前 Xcode UI 裡看到的 console

限制：

- 這支腳本讀的是「目前聚焦的 Xcode debug console」內容，不是系統層的 device log
- 若目前沒有有效的 debug session、console 為空、或焦點未能切到 console，腳本會失敗
- 腳本目前使用 Xcode 英文選單名稱：
  - `View`
  - `Debug Area`
  - `Activate Console`
  - 若你的 Xcode 是其他語系，可能需要改寫對應的 menu item 名稱

## 建議搭配方式

先執行 app：

```bash
Scripts/run_xcode.sh --wait 1
```

執行後再匯出 console：

```bash
Scripts/export_xcode_console.sh
```

這樣可以快速完成：

1. 喚起 Xcode
2. 觸發目前 scheme 的 `Run`
3. 將 debug console 內容落檔到 `logs/xcode/`
