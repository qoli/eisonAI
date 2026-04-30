# Copilot CLI Prompt Optimization Notes

本文記錄 `new_version.sh` 的 Copilot CLI 提示詞優化經驗。目標不是單純把提示詞壓到最短，而是在任務質量、內部自修能力、工具幻覺成本和總時間成本之間取得平衡。

## 背景

`new_version.sh` 需要讓 Copilot CLI 從 Notion 更新日誌頁面讀取最新版本內容，並覆寫：

- `fastlane/changelog.txt`：英文 plain text
- `telegram/changelog.md`：中文 Telegram markdown

使用模型為 `Qwen3.6-35B-A3B-bf16`。這個模型存在工具幻覺風險，常見成本來源包括：

- 調用不存在或參數錯誤的工具
- 重複檢查工具列表
- 使用 `shell input` / `read shell output` 這類不適合非互動流程的工具
- validator agent 調用方式錯誤，導致重試或 background/read_agent 額外輪次
- `--autopilot + -p` 下 stdout 不可靠，`task_complete` 結果可能不完整輸出

## 驗收標準

最終有效提示詞需要通過 10 次有效測試。每次有效 run 同時滿足：

- 外部檔案審計 PASS
- `events.jsonl` 中存在 `session.task_complete` 且 `success=true`
- 至少一次 `translation-validator` agent PASS
- prompt mode 為 `-i`
- 沒有把 `--autopilot + -p` stdout 當作完成依據

外部審計只作最終防線，不取代 Copilot 內部 validator 自修閉環。

## 最終候選提示詞

目前採用的提示詞核心如下：

```text
直接呼叫 Notion MCP 讀取 page 2e2c1b36c40180849002d41f8892a5c7，不要先檢查工具列表。只從主頁正文找純版本 heading：## x.y。
選數值最大的版本，只取該 heading 到下一個純版本 heading 前的內容；不要混入頁首子頁、說明文字或舊版本。

覆寫這兩個文件：
- <english_file>：英文 plain text，保留同一行 ## x.y 版本 heading，不要 HTML 或中文。
- <telegram_file>：中文 Telegram markdown，保留同一行 ## x.y 版本 heading，不要翻成英文。

父目錄已存在，直接寫入上述完整路徑；不要用 shell input 或 bash 建目錄/寫檔。
寫完後只呼叫 translation-validator agent 做唯讀驗證；validator 只讀兩個輸出檔，不讀 Notion/web/curl。
驗證：兩檔非空、各只有一個 ## x.y、版本一致、英文檔無 HTML/中文、Telegram 檔有中文、無舊版本 heading。
呼叫 validator 時帶 name=translation-validator 並同步等待；不要用 background/read_agent。validator FAIL 時由 main agent 修檔後再驗證；validator PASS 後才 task_complete。不要使用 web/browser/HTML，也不要呼叫其他 agent/subtask。
最後只輸出：SUCCESS/FAIL、version: x.y、validator: PASS/FAIL、files: written。
```

## 為什麼不是外部-only 驗證

外部-only 驗證速度較快，但有一個核心缺陷：main agent 失去內部改正能力。

實測中，外部-only prompt 可以讓 Copilot 寫出通過 shell 驗證的文件，但如果模型第一次寫錯，只有外層腳本能判定失敗，Copilot 本輪無法利用 validator 的具體錯誤原因自修。

`translation-validator` agent 方案的成本較高，但能形成閉環：

1. main agent 讀 Notion 並寫檔
2. translation-validator 唯讀檢查
3. validator FAIL 時返回具體錯誤
4. main agent 修檔
5. 重新 validator
6. validator PASS 後才 `task_complete`

這比單純外部 shell 驗證更符合 release automation 的質量要求。

## 關鍵失敗經驗

### 不要先檢查工具列表

「先檢查 notion MCP 是否存在」容易讓模型在工具認知上走偏，甚至在 Notion 可用時提前判定不可用。最終改成：

```text
直接呼叫 Notion MCP ... 不要先檢查工具列表。
```

### 不要使用相對輸出路徑

相對路徑曾導致模型截斷路徑，例如嘗試寫入 `/Volumes/Dat`。測試腳本後來強制將 output root 轉成絕對路徑。

### 明確禁止 shell input / bash 寫檔

模型曾調用 `Write shell input`，產生 `"shellId": Required` / `"delay": Required` validation error。提示詞加入：

```text
父目錄已存在，直接寫入上述完整路徑；不要用 shell input 或 bash 建目錄/寫檔。
```

### validator 要同步，不要 background

模型曾先缺 `name` 調用 validator，接著用 background agent，再用 `read_agent` 等待。這增加 request 和時間成本。提示詞加入：

```text
呼叫 validator 時帶 name=translation-validator 並同步等待；不要用 background/read_agent。
```

### validator 不應再讀 Notion

validator 曾嘗試讀 Notion 甚至使用 curl 核對來源，增加成本。最終要求：

```text
validator 只讀兩個輸出檔，不讀 Notion/web/curl。
```

來源抽取責任留給 main agent；validator 只驗證輸出物格式與語言分工。

### 不要依賴 `--autopilot + -p` stdout

GitHub issue `github/copilot-cli#2482` 和本地 session 都顯示：`--autopilot + -p` 下 stdout 不可靠，不能作為 `task_complete` 完成依據。

正確做法是監控：

```text
events.jsonl -> session.task_complete success=true
```

本輪測試使用 `-i`，並以 `events.jsonl` 作為完成信號。

## 成本數據

10 次有效驗收：

```text
logs/copilot_prompt_optimization/20260430-validator-10valid
```

平均成本：

- duration: `156.8s`
- requests: `8.7`
- API duration: `138100ms`
- input tokens: `364878`
- task invocations: `1.1`
- translation-validator invocations: `1.1`
- task validation failures: `0`
- tool validation failures: `0`

代表性舊版 validator prompt：

- requests: `18`
- API duration: `279704ms`
- input tokens: `893437`
- task validation failures: `2`
- task invocations: `2`

外部-only prompt 的 3 次樣本較快：

- requests avg: `6.0`
- API duration avg: `99796ms`
- input tokens avg: `362006`

但外部-only 不具備內部 validator 自修能力，因此不作為最終 release prompt。

## 結論

目前最佳平衡是：

- main agent 負責 Notion 讀取、版本判定、寫檔和修正
- `translation-validator` agent 只做唯讀輸出驗證
- 外部 shell 驗證只作最終審計
- completion 只信 `events.jsonl`，不信 stdout
- 使用 `-i`，避免 `--autopilot + -p` stdout/task_complete bug 路徑

這個方案比原始長 prompt 顯著降低時間成本，同時保留 validator agent 帶來的質量閉環。

## 推薦測試命令

```bash
EXPECTED_VERSION=2.9 \
COPILOT_TASK_COMPLETE_GRACE_PERIOD=10 \
COPILOT_MAX_AUTOPILOT_CONTINUES=10 \
COPILOT_MAX_TEST_ATTEMPTS=20 \
Scripts/test_copilot_prompt_optimization.sh 10 logs/copilot_prompt_optimization/manual-validator-10valid
```

測試結果看：

```bash
python3 Scripts/analyze_copilot_logs.py logs/copilot_prompt_optimization/manual-validator-10valid
```

## 後續調優方向

- 如果 Notion 頁面內容更長，觀察 validator 是否仍只讀輸出檔，避免回頭讀來源。
- 如果 validator 重試率升高，優先改善 main agent 寫檔提示，而不是增加外部規則。
- 如果 task invocations 平均超過 1.5，檢查是否又走到 background/read_agent 或 validator schema retry。
- 如果 tool validation failures 不為 0，優先從 session log 找出是哪一句提示誘發錯誤工具。
