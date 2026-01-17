---
source: https://developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets
crawled: 2025-12-04T09:39:17Z
---

# 顯示靜態與互動式片段 (Snippets)

**文章**

讓用戶查看 App Intent 的結果，並能立即執行後續操作。

## 概覽

透過使用 App Intents，您可以將 App 整合到系統中，允許用戶透過 Spotlight、控制中心、動作按鈕或 Siri 等系統體驗來執行操作。為了告知用戶 App Intent 操作的結果，Intent 可以返回一個靜態片段 (Static Snippet)。

您透過 App Intents 提供給系統的許多操作都很簡單，並且發生得很快。App Intents 可以返回一個互動式片段 (Interactive Snippet)，允許用戶直接在片段中執行操作，而不必查看靜態資訊。如果 App Intent 需要用戶進一步的操作，與其啟動 App 而讓用戶脫離當前的上下文，不如將 App Intent 改為顯示一個互動式片段，展示 Intent 的結果、確認操作的方式，或後續操作的按鈕。

例如，[doc://com.apple.AppIntents/documentation/AppIntents/adopting-app-intents-to-support-system-experiences] 範例 App 提供了一個查看附近地標詳細資訊的 App Intent。用戶可能會使用它來建立捷徑，並從 Spotlight 或動作按鈕執行該操作。當 App Intent 找到附近地標的資訊時，它會顯示一個互動式片段，其中包含最重要的資訊、一個將其加入最愛列表的按鈕，以及如果該地標需要門票則搜尋可用票務的按鈕。

### 顯示靜態片段

如果您的 App Intent 不需要後續操作，請返回一個靜態片段，讓用戶查看 App Intent 的結果。要從 App Intent 顯示靜態片段作為結果，請從 App Intent 的 `perform()` 方法返回一個視圖 (View)：

```swift
func perform() async throws -> some IntentResult {
    // ...
    
    return .result(view: Text("一些範例文字。").font(.title))
}
```

### 返回互動式片段

要顯示互動式片段作為 App Intent 的結果，請為您的操作建立一個 App Intent，或使用現有的 App Intent。例如，[doc://com.apple.AppIntents/documentation/AppIntents/adopting-app-intents-to-support-system-experiences] 範例 App 提供的地標資訊可能已經有一個 App Intent，用於尋找附近的地標並返回相關資訊：

```swift
struct ClosestLandmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Closest Landmark"

    func perform() async throws -> some ReturnsValue<LandmarkEntity> & ShowsSnippetIntent {
        let landmark = await self.findClosestLandmark()

        return .result(
            value: landmarkEntity // 返回關於地標的資訊。
        )
    }
}
```

要顯示片段而不是僅返回 App Entity，請修改 Intent 的 `perform()` 函數，使其除了現有的返回值外，還返回一個 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent]，這可以透過添加 `& ShowsSnippetIntent` 來實現。當您從 Intent 返回 [doc://com.apple.AppIntents/documentation/AppIntents/ShowsSnippetIntent] 結果時，即告知系統該操作將顯示互動式片段。在 [doc://com.apple.AppIntents/documentation/AppIntents/adopting-app-intents-to-support-system-experiences] 範例 App 中，前面範例更新後的 `perform()` 方法可能如下所示：

```swift
struct ClosestLandmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Closest Landmark"

    @Dependency var modelData: ModelData

    func perform() async throws -> some ReturnsValue<LandmarkEntity> & ShowsSnippetIntent {
        let landmark = await self.findClosestLandmark()

        return .result(
            value: landmark,
            snippetIntent: LandmarkSnippetIntent(landmark: landmark)
        )
    }
}
```

在這個範例中，Intent 透過宣告 `-> some ReturnsValue<LandmarkEntity>` 返回一個地標實體，並額外返回一個 `LandmarkSnippetIntent`。這個 Intent 是 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent] 的實作，負責處理片段的佈局和互動組件。

當您採用互動式片段時，您也許能夠重用現有的 Intent 並添加邏輯來顯示片段。如上例所示，您可以從 Intent 返回多個結果。透過保留現有的結果類型並額外返回片段 Intent，您可以避免破壞用戶使用該 Intent 舊版本建立的自訂捷徑。

### 建立互動式片段

如前一節所述，執行 App 操作的 Intent 可以返回一個 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent]。片段 Intent 建構片段的佈局並將其返回給系統，系統隨即顯示互動式片段。要返回互動式片段的視圖：

1. 建立一個符合 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent] 的 App Intent。
2. 確保 Intent 的 `perform()` 方法返回 [doc://com.apple.AppIntents/documentation/AppIntents/ShowsSnippetView]。

以下程式碼延續前面的範例，展示 `AppIntentsTravelTracking` App 如何從 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent] 返回一個 `LandmarkView`：

```swift
import AppIntents
import SwiftUI

struct LandmarkSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Landmark Snippet"

    @Parameter var landmark: LandmarkEntity
    @Dependency var modelData: ModelData

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let isFavorite = await modelData.isFavorite(landmark)

        return .result(
            view: LandmarkView(landmark: landmark, isFavorite: isFavorite)
        )
    }
}

extension LandmarkSnippetIntent {
    init(landmark: LandmarkEntity) {
        self.landmark = landmark
    }
}
```

注意視圖初始化器中的 `isFavorite` 參數。`LandmarkView` 指示地標是否已標記為最愛，並包含一個用於從最愛中添加或移除它的按鈕。`LandmarkView` 還包含一個按鈕，用於開始搜尋參觀該地標的門票。

### 審視片段 Intent 的生命週期

片段會一直保持可見，直到用戶將其關閉，並且與 SwiftUI 視圖類似，系統和用戶的操作可能會導致您的 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent] 在其生命週期中被多次建立和執行。

例如，地標範例程式碼專案的片段包含一個最愛按鈕，用於將附近地標從最愛列表中添加或移除。當用戶點擊最愛按鈕時，系統會執行 `FavoriteLandmarkIntent` 進行更改。它會丟棄片段的舊 SwiftUI 視圖，並再次執行 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent] 以提供新版本的片段，顯示用戶已將地標從最愛列表中添加或移除。

在片段 Intent 的 `perform()` 函數中，檢索 App 狀態——例如，當前地標是否為最愛——並返回更新後的片段，如上面的 `LandmarkSnippetIntent` 範例程式碼所示。

由於系統會重複建立並執行您的 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent]，請確保呼叫其 `perform()` 方法不會產生副作用：

- 如果您在 Intent 之間傳遞資料，請傳遞最少量的不可變資料。
- 避免長時間運行的任務，以確保片段看起來反應靈敏。
- 從共享物件獲取動態值，而不是將它們作為參數在 Intent 之間傳遞；例如，上面的 `LandmarkSnippetIntent` 使用 [doc://com.apple.AppIntents/documentation/AppIntents/AppDependency] 來獲取其 `modelData`。

### 建立片段序列並請求確認

透過互動式片段，您可以建立快速、流暢的互動，讓用戶無需離開當前上下文即可查看內容並執行一系列操作。例如，地標範例可能會顯示一系列的三個片段：

1. 當用戶執行「尋找最近」App Shortcut 時，上面描述的地標片段會出現。它包含一個搜尋附近地標門票的按鈕。
2. 當用戶點擊按鈕搜尋門票時，第二個片段出現，請求確認門票總數。當他們調整了門票數量並確認後，搜尋開始。
3. 當搜尋完成時，第三個片段出現，顯示門票數量的總金額和一個購買按鈕。

為了建立這個片段序列，[doc://com.apple.AppIntents/documentation/AppIntents/adopting-app-intents-to-support-system-experiences] App 使用了常規 App Intent、確認請求和片段 Intent 的組合。

首先，App 定義了 `FindTicketsIntent`，一個執行搜尋的常規 App Intent。在其 `perform()` 方法中，[doc://com.apple.AppIntents/documentation/AppIntents/AppIntent/requestConfirmation(conditions:actionName:dialog:showDialogAsPrompt:snippetIntent:)-3vewj] API 使用 `TicketRequestSnippetIntent` 顯示互動式片段供用戶輸入門票。

```swift
import AppIntents

struct FindTicketsIntent: AppIntent {

    // ...

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        let searchRequest = await searchEngine.createRequest(landmarkEntity: landmark)

        // 呈現一個允許用戶更改門票數量的片段。
        try await requestConfirmation(
            actionName: .search,
            snippetIntent: TicketRequestSnippetIntent(searchRequest: searchRequest)
        )
        
        // ...
    }
}

// ...
```

當用戶在 `TicketRequestSnippetIntent` 呈現的片段中輸入了門票數量後，他們確認門票數量，搜尋隨即開始。搜尋結果顯示在 `TicketResultSnippetIntent` 呈現的第三個片段中：

```swift
// ...

func perform() async throws -> some IntentResult & ShowsSnippetIntent {
    let searchRequest = await searchEngine.createRequest(landmarkEntity: landmark)

    // 呈現一個允許用戶更改門票數量的片段。
    try await requestConfirmation(
        actionName: .search,
        snippetIntent: TicketRequestSnippetIntent(searchRequest: searchRequest)
    )
    
    // 如果用戶確認了操作，執行門票搜尋。
    try await searchEngine.performRequest(request: searchRequest)

    // 顯示門票搜尋的結果。
    return .result(
        snippetIntent: TicketResultSnippetIntent(
            searchRequest: searchRequest
        )
    )
}

// ...
```

透過使用 `requestConfirmation()` API 顯示片段，片段包含取消操作的選項。如果用戶不確認門票數量，App Intent 就不會繼續其 `perform()` 函數，也不會執行搜尋或顯示另一個片段。

### 重新載入片段以顯示更新的資料

在上面的範例中，三個片段按順序出現，每個片段替換前一個片段。如果一個片段在螢幕上停留了一段時間；例如，如果您像範例中那樣執行搜尋；請重新載入片段以讓用戶知道搜尋正在進行中。同樣地，如果其底層資料發生變化，也請重新載入片段。

要重新載入片段，請使用由 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent] 定義的 [doc://com.apple.AppIntents/documentation/AppIntents/SnippetIntent/reload()] 函數。以下範例將其添加到搜尋方法的結尾閉包中：

```swift
// ...

func perform() async throws -> some IntentResult & ShowsSnippetIntent {
    // ...
        
    // 如果用戶確認了操作，執行門票搜尋。
    try await searchEngine.performRequest(request: searchRequest) {
        // 建立並重新載入 TicketResultSnippetIntent。
        TicketResultSnippetIntent.reload()
    }

    // 顯示門票搜尋的結果。
    return .result(
        snippetIntent: TicketResultSnippetIntent(
            searchRequest: searchRequest
        )
    )
}

// ...
```

## 互動式片段 (Interactive Snippets)

- **SnippetIntent**: 一個在螢幕上呈現互動式片段的 App Intent。