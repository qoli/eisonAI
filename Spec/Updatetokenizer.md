# [SPEC] 更換 tokenizer 計算器

原因：
GPT 2 BPE tokenizer 計算表現誤差極大，高達 2.7 倍誤差。
從而無法滿足 chunk 切割執行正確的預測。

## 計劃更換方案

針對 Safari Extension 和 App 原生端；
分別使用
- https://github.com/niieani/gpt-tokenizer （驅動 Safari Extension）
- https://github.com/narner/TiktokenSwift  （驅動 App 原生端）

新的 Tokenizer 以 o200k_base 作為計算基準。

### Safari Extension 端
庫源代碼參考：
/Volumes/Data/Github/gpt-tokenizer

集成方法：
把 https://unpkg.com/gpt-tokenizer/dist/o200k_base.js 下載到 `Shared (Extension)/Resources/webllm` 路徑，以 js 文件形式集成


### App 端
庫源代碼參考：
/Volumes/Data/Github/TiktokenSwift

SPM 已經完成 on local 的方式集成，TARGETS 為 iOS 端