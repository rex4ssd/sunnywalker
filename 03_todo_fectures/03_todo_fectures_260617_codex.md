# SunnyWalker GUI 與親子市場建議 260617

目的：讀完 `03_todo_fectures.md`，並 review 目前 repo 的 GUI、資料模型與截圖後，整理我對 4 到 12 歲兒童與母嬰市場的產品方向、1+1>2 組合，以及可落地的技術實作路線。

## 一句話結論

SunnyWalker 不要只定位成「兒童鬧鐘」。它更適合被包成「孩子一天例行任務的聲音陪伴系統」。

現在 repo 已經有幾個很好的底座：鬧鐘可靠性、家長錄音、語音關閉、起床紀錄、吉祥物、水彩童趣風格、家長 gate、Pro IAP。真正的下一步不是多加單點功能，而是把這些能力組成一個閉環：

家長錄一句話 -> 孩子完成一個生活任務 -> App 給孩子正回饋 -> 留下可回看的成長紀錄 -> 家長更願意每天使用與付費。

這樣「鬧鐘 + 錄音 + 任務 + 紀錄」會比各自獨立功能更強，形成 1+1>2。

## Repo 現況觀察

### 目前很有優勢的地方

1. 視覺底子已經有記憶點
   - `HomeView` 有時間場景、雲、紙感、水彩背景。
   - `MascotView` 已經有可切換吉祥物與 tap greeting。
   - `RewardView` 已有成功動畫、音效與 confetti。
   - 這些都很適合兒童市場，不需要推倒重做。

2. 家長信任感做得比一般鬧鐘 app 好
   - 家長 gate 已存在，IAP 放在家長區。
   - 目前設計偏本機、無廣告、無追蹤，這對母嬰市場非常重要。
   - `ProUpgradeView` 的語氣冷靜，沒有倒數、假折扣、外部連結，方向正確。

3. 聲音功能是核心差異化
   - `VoiceLibraryView`、錄音、裁剪、匯入、命名、播放都已有基礎。
   - `AlarmRingView` 已經把聲音、語音辨識、按鈕 fallback、起床紀錄串起來。
   - 這不是普通鬧鐘可輕易複製的價值。

4. 有資料閉環雛形
   - `Alarm`、`VoiceClip`、`WakeRecord` 都已存在。
   - 起床紀錄還能匯出 Markdown，這代表日後做成長日記、週報、家長回顧都很自然。

### 目前比較可惜的地方

1. 主畫面仍像「成人鬧鐘列表」
   - 現在鬧鐘卡主要展示時間、label、weekday、toggle。
   - 對孩子來說，「07:30」不如「上學任務」好理解。
   - 對家長來說，這也比較像工具，不像會陪孩子建立生活節奏的產品。

2. 新增鬧鐘頁是欄位導向，不是情境導向
   - 目前流程是時間、標籤、重複、鈴聲、口令、背景模式。
   - 這對成人合理，但對親子市場更有賣點的流程應該是：
     「這是什麼任務？」->「要在什麼時間發生？」->「想對孩子說什麼？」->「完成後給什麼鼓勵？」

3. 錄音功能像工具，還沒有被包成情緒價值
   - 裁剪頁、錄音管理頁功能強，但語意仍是音檔管理。
   - 母嬰市場真正買單的是「媽媽的聲音」「爸爸的鼓勵」「長大的紀念」，不是「可以管理 m4a」。

4. 起床紀錄目前偏工程統計
   - 回應秒數、方式、日期有用，但可再轉成家長更有感的語言：
     「這週 5 天有 4 天自己起床」
     「今天比昨天快 18 秒」
     「連續 3 天完成上學任務」

## 建議產品定位

### 新定位

SunnyWalker = 孩子的生活任務夥伴，加上家長聲音記憶盒。

核心不是「提醒時間到了」，而是：

- 孩子看得懂接下來要做什麼。
- 家長用自己的聲音陪孩子完成例行生活。
- 每一次完成都留下可回看的成長痕跡。

### 主要族群拆分

1. 4 到 6 歲：識字少，靠圖像、聲音、角色、單一步驟。
   - 主畫面要幾乎無字也能懂。
   - 任務以圖示、大按鈕、家長語音為主。
   - 關閉方式以按鈕、拖曳、找圖形為主，不建議強依賴語音辨識。

2. 7 到 9 歲：可接受簡短文字與簡單挑戰。
   - 可以加入「說出口令」「完成小任務」「連續天數」。
   - 可以開始用貼紙、稱號、任務徽章。

3. 10 到 12 歲：不想被當小小孩。
   - GUI 要能選比較成熟的主題。
   - 重點可轉成自律、學習、睡眠節奏、晨間任務。
   - 可以提供簡潔模式，少一點幼兒感。

## 1+1>2 的產品組合

### 組合一：鬧鐘 + 任務卡

把「鬧鐘」改成「生活任務卡」。

例子：

- 上學
- 刷牙
- 喝水
- 寫功課
- 閱讀
- 睡前故事
- 午睡起床
- 吃藥

主畫面不要只顯示鬧鐘列表，而是顯示：

- 下一個任務是什麼
- 還有多久開始
- 這個任務是誰的聲音
- 完成後會得到什麼小獎勵

技術方向：

- 在 `Alarm` 加 `routineKind: RoutineKind?`，不要跟現有 `AlarmTaskType` 混用。
- 現有 `AlarmTaskType` 是關閉方式，長期可以改名成 `DismissTaskType`。
- 新增 `RoutineKind` enum：
  - `school`
  - `brushTeeth`
  - `drinkWater`
  - `homework`
  - `reading`
  - `bedtime`
  - `napWake`
  - `medicine`
  - `custom`
- 每個 `RoutineKind` 提供：
  - displayName
  - icon system name 或自製圖像
  - default color
  - default phrases
  - default reward text
  - default suggested time

GUI 方向：

- `AlarmListView` 的卡片改成 `RoutineCard`。
- 時間是副資訊，任務圖像和任務名稱是主資訊。
- 例如「上學囉」卡片左側是書包或太陽圖示，中間是任務文字，右側才是時間與開關。

### 組合二：鬧鐘 + 家長錄音 + 聲音時光機

`03_todo_fectures.md` 提到 Voice Time Capsule，這很適合當 Pro 招牌功能。

不是只讓家長錄「起床囉」，而是讓家長建立幾種聲音：

- 今天早上的一句鼓勵
- 睡前故事
- 考試前加油
- 生日當天打開的語音
- 開學第一天的語音
- 未來某一天給孩子的話

這個功能的情緒價值很高，且 local scheduling 就能完成，不必急著上後端。

技術方向：

- 新增 `VoiceMoment` 或 `VoiceCapsule` model：
  - `id`
  - `title`
  - `clipID`
  - `kind: CapsuleKind`
  - `deliverAt: Date?`
  - `routineKind: RoutineKind?`
  - `isDelivered`
  - `createdAt`
- `CapsuleKind`：
  - `morning`
  - `bedtime`
  - `encouragement`
  - `birthday`
  - `futureLetter`
  - `custom`
- 用 `UNUserNotificationCenter` 做本機排程提醒。
- 不需要先做 CloudKit，先把「本機可靠 + 隱私」打穩。

GUI 方向：

- 新增一個「聲音信箱」或「時光信箱」入口。
- 孩子端看到的是幾個封好的信件，不一定能提前打開。
- 家長端看到的是排程、錄音、分類、是否已送達。

1+1>2 的原因：

鬧鐘解決每天打開 app 的理由；聲音時光機讓家長產生情感投入；兩者加起來會形成長期留存。

### 組合三：起床紀錄 + 成長日記

目前 `WakeHistoryView` 已能記錄回應時間與關閉方式。下一步不要只做統計，要做成「成長紀錄」。

家長會在意的不是每筆秒數，而是孩子是否越來越能自己完成生活節奏。

建議加：

- 本週完成率
- 連續完成天數
- 哪個任務最穩
- 哪天需要家長協助
- 本週值得鼓勵的一句話
- 可匯出一張週報圖片或 Markdown

技術方向：

- 保留 `WakeRecord`，新增 computed summary builder：
  - `RoutineSummaryService`
  - `WeeklyWakeSummary`
  - `RoutineCompletionStats`
- 如果新增 `routineKind`，`WakeRecord` 也要 snapshot：
  - `routineKindRaw`
  - `voiceClipID`
  - `rewardID`
- 現有 Markdown export 可擴充成：
  - 統計總覽
  - 本週故事
  - 任務完成表
  - 家長備註

GUI 方向：

- 起床紀錄列表上方加一個本週摘要。
- 列表卡片保留，但語氣變溫柔：
  - 「今天自己起床了」
  - 「花了 8 秒完成」
  - 「用說話關閉」
  - 「連續第 3 天」

### 組合四：任務完成 + 貼紙書

孩子端需要可感知的回饋。現在 `RewardView` 是一次性的慶祝，但可以進一步變成可累積的貼紙書。

不要做太重的遊戲，不要讓孩子沉迷。做輕量收藏就好。

技術方向：

- 新增 `RewardSticker` model 或本機 JSON catalog：
  - `id`
  - `routineKind`
  - `assetName`
  - `unlockRule`
  - `rarity`
- 新增 `StickerUnlock` model：
  - `stickerID`
  - `unlockedAt`
  - `sourceWakeRecordID`
- `RewardView` 完成後顯示本次拿到的貼紙。
- `SettingsView` 或孩子首頁可加「貼紙書」入口。

GUI 方向：

- 貼紙不需要商業化成抽卡，避免親子市場反感。
- 用「今天完成上學任務，得到太陽貼紙」這種正向回饋。
- 4 到 6 歲用大貼紙；10 到 12 歲可改成徽章或成就。

### 組合五：睡前故事 + 起床任務

這是最符合母嬰市場的 1+1>2。

早上：家長聲音叫醒。
晚上：家長聲音陪睡。
週末：回看聲音與紀錄。

SunnyWalker 就從「早上鬧鐘」變成「一天兩端的親子節奏」。

技術方向：

- `RoutineKind.bedtime`
- `BedtimeStory` 或直接用 `VoiceMoment(kind: .bedtime)`
- `BedSideManager` 已有床邊模式，可接睡前故事模式。
- 睡前故事播放要支援：
  - 播放一次後自動停止
  - 螢幕漸暗
  - 不開互動獎勵，避免睡前越玩越醒

GUI 方向：

- 晚上首頁自動轉成睡前模式：
  - 深色低亮度
  - 吉祥物睡覺
  - 下一個睡前故事
  - 明早第一個任務

## GUI 改造方向

### 主畫面

目前主畫面有漂亮背景、大時鐘、吉祥物、鬧鐘卡。建議改成三層：

1. 上方：現在時間與場景
2. 中間：下一個任務 hero
3. 下方：今日任務列

下一個任務 hero 可以顯示：

- 任務圖像
- 任務名稱
- 倒數時間
- 聲音來源，例如「媽媽的早安」
- 一個很大的「我準備好了」或「聽聽看」按鈕

鬧鐘列表不需要完全消失，但要降級成家長或進階資訊。

### 新增鬧鐘流程

建議把 `AlarmEditorView` 拆成 wizard：

1. 選任務
2. 選時間與重複
3. 選聲音或錄一句話
4. 選關閉方式
5. 完成預覽

對家長的感覺會從「我在設定一個鬧鐘」變成「我在幫孩子建立一個生活習慣」。

技術可以先不大改資料模型，先做 UI wrapper：

- 新增 `RoutineWizardView`
- 內部最後仍寫入 `Alarm`
- 初期 `routineKind` 可以先存在 `Alarm.label` 或新增 optional 欄位
- 穩定後再完整 migration

### 錄音頁

保留現有功能，但加一層情境入口：

- 錄一段早安
- 錄一段睡前故事
- 錄一段加油
- 錄一段未來的話

每個入口背後都用同一套 `VoiceClipRecorderSheet`，但家長看到的是用途，不是音檔操作。

### 起床/任務完成畫面

`AlarmRingView` 建議根據 `routineKind` 換文案和圖像：

- 上學：書包、太陽、出門
- 刷牙：牙刷、泡泡
- 喝水：水杯
- 睡前：月亮、安靜色調
- 閱讀：書本

這樣同一套鬧鐘引擎可以支撐多個市場情境。

### Pro 頁

目前 Pro 頁功能說明偏限制解除，例如更多鬧鐘、更多錄音、錄音更長。建議文案往情緒價值調整：

- 保存更多家人的聲音
- 建立聲音時光信箱
- 解鎖更多任務貼紙
- 匯出孩子的成長週記
- 跨裝置家庭備份，後期再做

限制解除仍可放，但不要是主敘事。

## 技術實作路線

### Phase 1：低風險 GUI 重包裝

目標：不大動 AlarmKit 與排程，只讓產品語意從鬧鐘轉成任務。

工作：

1. 新增 `RoutineKind` enum。
2. `Alarm` 新增 optional `routineKindRaw: String?`。
3. `AlarmListView` 卡片改成任務卡樣式。
4. `AlarmEditorView` 上方新增「任務類型」選擇。
5. `AlarmRingView` 根據任務換 title、icon、reward 文案。
6. `WakeRecord` snapshot `routineKindRaw`。

風險低，因為排程仍然沿用現有 `Alarm`。

### Phase 2：聲音信箱 MVP

目標：把現有錄音能力變成情緒功能。

工作：

1. 新增 `VoiceCapsule` model。
2. 新增 `VoiceCapsuleListView`。
3. 新增 `VoiceCapsuleEditorView`。
4. 使用現有 `VoiceClipRecorderSheet` 錄音。
5. 用 `UNUserNotificationCenter` 做本機送達提醒。
6. 送達後進 App 顯示信件卡，播放錄音。

第一版只做本機，不做同步。

### Phase 3：成長週報

目標：提升家長留存與付費理由。

工作：

1. 新增 `RoutineSummaryService`。
2. `WakeHistoryView` 上方加入 weekly summary。
3. Markdown export 加入週報摘要。
4. 可選：輸出一張分享圖片，但 Kids Category 要避免外部社交導流語氣。

### Phase 4：貼紙書

目標：讓孩子願意回來完成任務。

工作：

1. 新增貼紙 catalog。
2. `RewardView` 完成後解鎖貼紙。
3. 新增 `StickerBookView`。
4. 任務、連續天數、不同時間段對應不同貼紙。

### Phase 5：家庭同步

目標：Pro v2，不宜太早做。

方向：

- 優先 CloudKit private database。
- 兒童語音預設私有，不公開。
- 家庭共享要重新檢查 Kids Category、隱私政策與 App Privacy。
- 不建議早期做 LINE 設定語音，第三方與後端會讓審核和隱私風險上升。

## 具體資料模型草案

```swift
enum RoutineKind: String, Codable, CaseIterable {
    case school
    case brushTeeth
    case drinkWater
    case homework
    case reading
    case bedtime
    case napWake
    case medicine
    case custom
}

enum DismissTaskType: String, Codable {
    case button
    case voice
    case math
}

@Model
final class VoiceCapsule {
    @Attribute(.unique) var id: UUID
    var title: String
    var clipID: UUID
    var kindRaw: String
    var routineKindRaw: String?
    var deliverAt: Date?
    var isDelivered: Bool
    var createdAt: Date
}

@Model
final class StickerUnlock {
    @Attribute(.unique) var id: UUID
    var stickerID: String
    var unlockedAt: Date
    var sourceWakeRecordID: UUID?
}
```

現有 `AlarmTaskType` 建議不要再承擔「任務類型」語意。它現在表示關閉方式，名字容易混淆。可以先保留不動，未來 migration 時改名或新增 wrapper。

## App Store 與母嬰市場注意事項

1. 不要把兒童語音公開到網路。
2. 不要把分享、LINE、社群投稿當早期核心。
3. Pro 購買入口繼續放家長 gate 後。
4. 孩子端不要出現銷售文案。
5. 家長端強調：
   - 本機優先
   - 無廣告
   - 無追蹤
   - 聲音屬於家庭
6. 睡前功能要避免刺激性動畫與過強遊戲化。
7. 4 到 12 歲跨度大，必須提供主題成熟度：
   - 小童：可愛、貼紙、大圖示
   - 大童：簡潔、自律、徽章、少幼兒感

## 最推薦先做的三件事

### 第一優先：任務卡化

把鬧鐘從「時間列表」變成「生活任務卡」。這是最能立即改善 GUI 與市場定位的改動。

原因：

- 改動相對小。
- 可直接提升兒童理解力。
- 可讓 App Store 截圖更容易講故事。
- 後續聲音信箱、貼紙書、週報都能掛在任務上。

### 第二優先：聲音信箱 MVP

把 `03_todo_fectures.md` 的 Voice Time Capsule 做成本機版。

原因：

- 情緒價值高。
- 技術可控。
- 不需後端。
- 非常適合作為 Pro 招牌功能。

### 第三優先：起床紀錄週報

把 WakeRecord 從列表變成家長看得懂的成長回饋。

原因：

- 現有資料已經有。
- 能讓家長感覺 App 在幫忙養成習慣。
- 可支撐 Pro 的「成長記錄」價值。

## 我會避免的方向

1. 早期不要做公開聲音庫。
   - 兒童語音、審核、內容安全、家長信任都太敏感。

2. 早期不要把 LINE 設定語音當主線。
   - 後端、第三方、Kids Category 風險都高。

3. 不要把 Pro 只包成解除限制。
   - 母嬰市場更在意陪伴、紀念、安心與孩子習慣養成。

4. 不要過度遊戲化。
   - 貼紙和徽章可以，但不要做抽卡、排名、連續壓力。

5. 不要讓設定頁越來越重。
   - 家長功能可以多，但新增流程要情境化，孩子端要保持單純。

## 總結

SunnyWalker 目前已經不是從零開始。它缺的不是技術能力，而是把既有能力重新包成一個親子市場一眼懂的故事。

最好的 1+1>2 是：

鬧鐘可靠性 + 家長聲音 = 孩子願意醒來。

家長錄音 + 聲音時光機 = 家長願意留下來。

任務卡 + 貼紙獎勵 = 孩子願意每天完成。

起床紀錄 + 成長週報 = 家長願意付費。

全部合起來，SunnyWalker 會從「可愛鬧鐘」變成「孩子生活節奏與家庭聲音記憶的工具」。這個定位更貼近 4 到 12 歲與母嬰市場，也比較有長期產品生命力。
