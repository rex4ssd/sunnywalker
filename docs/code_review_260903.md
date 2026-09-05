# SunnyWalker 整體 review（2026-09-03）

> 對應 todo「功能越來越多，整個 review，讓 app 的 code 更好（覆用性更高），及幫我想怎麼讓這麼多的
> 功能簡單化讓 user 覺得好用，用不到的功能也不會佔著礙眼」。
> 分三段：**已經改掉的**、**建議下一輪改的**、**UX 簡化原則**。

## 一、已經改掉的（本次 commit 內）

### 1. 路徑與 id 的「唯一正本」

| 以前 | 現在 |
|---|---|
| `Documents/Recordings/<name>.m4a` 在 11 處各拼一次 | `AppPaths.recordingURL(named:)` / `recordingExists(named:)` |
| `Library/Sounds` 在 8 處各拼一次 | `AppPaths.soundURL(named:)` / `ensureSoundsDirectory()` |
| 通知 id 字串在 4 處各拼（schedule / cancel / cancelNags / deleteAlarm） | `AlarmNotificationIDs`（builders + `all(for:)` / `followUps(for:)`） |
| 16-bit PCM CAF 的 outSettings 抄了 4 份 | `AlarmSoundExporter.writePCMCAF(_:to:)` |

**順手修掉的真 bug**：`AlarmListView.deleteAlarm` 以前只清 baseline 7 顆通知，切段堆疊（`-rep-k`）
與報時連報（`-chime-k`）的一次性通知會留在系統裡照響——鬧鐘已經不在清單上卻還在響。
現在刪除一律 `AlarmScheduler.cancel(id)` → `AlarmNotificationIDs.all(for:)`。

### 2. 檔案切分

* `SettingsView` 從 `HomeView.swift` 尾巴（500 行）搬到 `Views/Settings/SettingsView.swift`。
  以前不拆的理由「新檔要加 target membership」在 xcodegen 資料夾 glob 下早已不成立。
* 報時卡從 `AlarmEditorView`（1200 行）抽成 `ChimeCardView`；編輯器只剩綁定與儲存。
* `AlarmKind`（alarm / chime / todo）收成一個 enum；首頁卡片 switch 一次，不再各處判 `isTodo` / `isChimeAlarm`。

### 3. 主執行緒 I/O（選音檔／錄音頁「頓」的來源）

* `AlarmSoundExporter.exportLockScreenCAF`（整段錄音讀進記憶體再寫 CAF）以前在 main 同步跑：
  選錄音當鈴聲、錄完自動匯出、App 更新後的自癒重匯出，三條路都卡 main。現在全部 `Task.detached`。
* `VoiceClipRow` 每次 body 重算都 `stat` 檔案大小（五顆錄音＝五次同步讀檔 × 每次捲動）→ 改成進列
  `.task` 讀一次。
* 首頁三層常駐動畫（雲 30fps、吉祥物 24fps、紙紋）在被 sheet 蓋住時仍全速重繪 →
  `SheetPresenceTracker`：編輯器／設定／鈴聲庫／錄音頁蓋上來就暫停。
* SwiftData：`modelContext.delete` 之後 sheet 收合動畫仍會讀 `clip.name` → 兩個清單都過濾 `isDeleted`，
  刪除前先放掉詳情 sheet 的參照。**這是「有時整個 crash」最可能的根因之一**；但架上版拉不到 log，
  所以同時接了 `KidsDiagnostics`（MetricKit）——下次 App Store 版再閃退，`Documents/diagnostics/`
  會有 stack。

### 4. 報時試聽的孤兒檔

編輯器每按一次「試聽」就在 `Library/Sounds` 留一個 `chime_*.caf`，永不清理。改成寫到 tmp、同名覆蓋。

## 二、建議下一輪改的（本次刻意沒動，理由附上）

1. **AppSettings 的五條群組平行陣列**（`groupNames` / `groupMascots` / `groupActiveStates` /
   `groupChimeStates` / `groupTodoStates`，各配 get/set 補長度的樣板）→ 一個 `[GroupSettings]`。
   沒動的原因：五個 UserDefaults key 已在線上，換結構要寫遷移；報時／待辦互斥邏輯也在裡面，
   單獨一輪比較安全。
2. **`AlarmScheduler.swift` 仍是兩個責任**：UNNotification 排程 + `AlarmSoundUpgradeHealer`。
   healer 應該搬到 `Services/AlarmSoundUpgradeHealer.swift`（純搬檔，零風險）。
3. **`BackgroundListeningManager`（背景聆聽）已是 dormant 功能**（AlarmKit 授權時永遠不啟動、設定頁
   開關也拿掉了）。HomeView 還有 4 處在同步它。建議整段標 `@available(*, deprecated)` 或直接刪，
   HomeView 少 40 行。
4. **`Alarm.requireAppToStop`（貪睡）已於 06-10 廢除**，但 `scheduleNagsIfNeeded` / `StopAlarmIntent`
   的 strict 分支還在。同上，可整批清。
5. **`AlarmEditorView.EditorSnapshot`** 每加一個欄位要改三處（struct / currentSnapshot / 兩個 init 的
   baseline）。可改成 `static func snapshot(of alarm:)` + `init` 時 `baseline = Self.snapshot(...)`，
   新欄位只加一處。
6. **MarkdownAlarmIO** 不匯出報時／待辦／區間欄位（匯出再匯入會變一般鬧鐘）。KidsLineTable 已支援
   中段自由欄，可補 `kind=chime;end=07:30;every=5` 這類可選欄。

## 三、UX 簡化：把「用不到的」收起來，不是刪掉

原則：**每個畫面只露「大多數家長會動的」，其餘一律可展開、且改過的人進頁自動展開。**

已套用：

* 設定頁 →「進階設定」收：循環播放間隔、切段響鈴（持續／間隔）、自動停止時間、錄音自動命名加長。
  設定頁從 11 段變 8 段。
* 新增鬧鐘頁 →「進階選項」收：溫和提醒模式、口令關閉。新增鬧鐘只剩 時間／標籤／重覆／鈴聲 四張卡；
  這顆鬧鐘若已開過其中之一，進頁自動展開。
* 家長頁尾段改用家族共用件（家長閘 → 評分 → Pro → 更多 rexcode → 版本），跟另外 14 個 app 一致；
  自家的「暫時解鎖」段與「Pro」段刪掉（功能沒少，位置統一了）。

建議下一輪：

* **首頁「＋」的種類選擇**：現在鬧鐘是不是報時／待辦，取決於「這顆放進哪一組、那一組有沒有開報時」
  ——這是三層間接。更直覺的是「＋」跳一個三選一（鬧鐘／報時／待辦），群組只是「給誰」。
  資料模型不用改（`AlarmKind` 已經是單一判斷點），改的是編輯器的入口。
* **群組功能預設關**是對的；但群組列上的鈴鐺／氣球 icon 沒有文字，家長靠長按才知道意思。
  建議改成每組一個「用途」下拉（鬧鐘／報時／待辦），互斥邏輯自然消失。
* 12h/24h、依時段排列 這種「看一次就懂」的設定可以留在頂層；主題（吉祥物／向日葵）是孩子的事，
  可考慮從家長頁搬到首頁長按吉祥物（不需家長閘）。
