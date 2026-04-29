# 896 Token Chunk / maxChunks=5 採集量紀錄

本文記錄本地 probe 在 `chunkTokenSize = 896`、`maxChunks = 5` 下，對兩個長文本樣本實際會採集多少內容。

資料來源為本地 dry-run 報告：

```text
logs/allowed-chunk-probe/allowed-chunk-probe-2026-04-29T11-03-52Z.json
```

## 測試條件

- 測試模式：dry-run，未呼叫 `afm-cli` 實際推理。
- 分段大小：`896` estimated tokens。
- 最大段數：`5`。
- 理論最大採集量：`896 * 5 = 4480` estimated tokens。
- token 口徑：Swift probe 腳本中的 eison heuristic，等價於 Safari Extension fallback 的 `CJK + nonCJK / 4` 估算邏輯。
- 重要限制：這不是 Apple Foundation Models 的真實 tokenizer，只能代表 eisonAI 目前長文分段估算口徑。

## 樣本 1：Wikipedia `Artificial intelligence`

- 來源：`https://en.wikipedia.org/wiki/Artificial_intelligence`
- 原文長度：`84206` characters。
- 全文估算 token：`21052`。
- 實際採集 chunk 數：`5`。
- 每段估算 token：`896 + 896 + 896 + 896 + 896`。
- 採集估算 token：`4480`。
- 未採集估算 token：`16572`。
- token 採集比例：`4480 / 21052 = 21.28%`。
- 採集 characters：`3584 + 3583 + 3584 + 3584 + 3583 = 17918`。
- character 採集比例：`17918 / 84206 = 21.28%`。

結論：在此設定下，Wikipedia 長文只會採集前約五分之一內容；後約四分之三以上內容會被截掉。

## 樣本 2：GitHub issue `rust-lang/rust#152334`

- 來源：`https://github.com/rust-lang/rust/issues/152334`
- 原文長度：`52513` characters。
- 全文估算 token：`13129`。
- 實際採集 chunk 數：`5`。
- 每段估算 token：`896 + 896 + 896 + 896 + 896`。
- 採集估算 token：`4480`。
- 未採集估算 token：`8649`。
- token 採集比例：`4480 / 13129 = 34.12%`。
- 採集 characters：`3584 + 3584 + 3584 + 3584 + 3579 = 17915`。
- character 採集比例：`17915 / 52513 = 34.11%`。

結論：在此設定下，GitHub 長 issue 只會採集前三分之一左右內容；後約三分之二內容會被截掉。

## 合併觀察

兩個樣本合併後：

- 全文估算 token：`21052 + 13129 = 34181`。
- 採集估算 token：`4480 + 4480 = 8960`。
- 未採集估算 token：`16572 + 8649 = 25221`。
- token 採集比例：`8960 / 34181 = 26.21%`。
- 全文 characters：`84206 + 52513 = 136719`。
- 採集 characters：`17918 + 17915 = 35833`。
- character 採集比例：`35833 / 136719 = 26.21%`。

也就是說，`896 * 5` 這套設定在這兩個長文本樣本上，平均只會採集約四分之一內容。

## 對長文 Pipeline 的含義

目前長文切段是從文章開頭連續切 `maxChunks` 段，不是抽樣、滑窗或全文覆蓋。因此 `maxChunks=5` 不是「讀完整篇文章後壓縮」，而是「最多讀前 4480 estimated tokens」。

如果文本長度遠超 `chunkTokenSize * maxChunks`，後面的內容不會進入 reading anchors，也不會進入最終 anchors summary。

## AFM 實測風險

後續 smoke test 顯示，`chunkTokenSize = 896`、`maxChunks = 1` 時：

- Wikipedia 第一段可成功呼叫 `afm-cli`。
- GitHub issue 第一段觸發 `context_limit`。

這表示 code/log 類內容在 Apple Foundation Models 上可能比 eison heuristic 估算更容易超窗。換句話說，`896` 即使在 dry-run 採集量上已經不高，對 AFM 實際 context window 仍可能偏大。

## 初步判斷

`896 / maxChunks=5` 的好處是降低單段 prompt 尺寸，但代價是覆蓋率很低：

- 對 21k estimated-token 的百科長文，只覆蓋約 `21%`。
- 對 13k estimated-token 的 GitHub issue，只覆蓋約 `34%`。

如果目標是穩定不撞 AFM context wall，`896` 可能仍不夠保守；如果目標是長文閱讀覆蓋率，`maxChunks=5` 明顯不足。這兩個目標需要分開設計：單段安全大小要靠 AFM 實測找上限，全文覆蓋率則要靠提高 `maxChunks`、滑窗、抽樣，或分層 reduce。
