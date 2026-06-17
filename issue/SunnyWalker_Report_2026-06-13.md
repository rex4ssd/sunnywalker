# SunnyWalker 提醒模式響鈴修復報告

**日期：** 2026-06-13
**Commit：** `b2e0b01`（branch `dev/auto`，5 檔 +224/−54）
**影響功能：** 提醒模式（per-alarm Time-Sensitive 通知，溫和、自動停）的鎖屏／殺 App 響鈴

---

## 一句話總結

iOS 會把「過長」的自訂通知音整顆退成約 2 秒的預設音（門檻遠低於官方文件寫的 30 秒），原本「把錄音 loop 成 29 秒」的做法因此失效。改成「短 CAF＋堆疊多顆秒級錯開的通知」鋪滿約 30 秒，並讓既有鬧鐘自動痊癒。真機已驗證 pass。

---

## 問題

提醒模式在「殺 App＋關屏」下，提醒聲昨天還能重複播滿約 30 秒，今天只剩約 2 秒就自動消失。關鍵在於：**同一個 App Store 核准版**昨天於 iPhone 15 實測 pass、今天卻 fail，剛重編的 Xcode 版也 fail。代表行為改變來自裝置／系統端，不是程式改壞。

## 診斷（逐步排除）

第一步比對程式碼：自昨天能用的 build 9 之後，唯二的 commit 只動了 UI 導覽，完全沒碰音效匯出與通知排程路徑，排除「code regression」。

第二步在排程處加上一行永遠輸出的量測 log，量到正在使用的 CAF 為 `29.0s / frames=1278900 / 2,561,896 bytes`。換算：1278900 ÷ 44100 = 29.0 秒；1278900 × 2 bytes（mono 16-bit）= 2,557,800，加上約 4KB header 剛好等於檔案大小。也就是說這是一個**完整、未截斷**的 29 秒檔，排除「檔案壞掉／header 灌水」。

第三步推論：既然程式看到的是完整 29 秒檔、iOS 卻只播約 2 秒，問題出在 iOS 播放端。

第四步做對照實驗：暫時讓 exporter 輸出不 loop 的 4.6 秒短 CAF，真機在殺 App＋關屏下**完整播出 4～5 秒的人聲**。這一刀切開了結論——iOS 是「拒絕長檔、完整播短檔」。

## 根因

iOS 對自訂通知音（`UNNotificationSound`）「完整播放」的有效長度，**遠低於**官方文件寫的 30 秒。長檔（實測 29 秒）會被 iOS 在 delivery 時整顆退成約 2 秒的預設音；短檔（4.6 秒）則完整播出。文件只保證自訂音「不超過 30 秒才會被接受」，從未保證整段都會播完——這個實際門檻被 Apple 收緊了。時間線也吻合：今天 AlarmKit entitlement 剛被核准（系統狀態變化），可能伴隨 iOS 行為調整。

結論：把檔案「做得更好」無法解決，這是平台政策面的限制，必須改變策略。

## 修法

核心想法是「不靠單一長音，改靠多顆短音堆疊」：

1. **exporter 不再 loop 成 29 秒**，改輸出短的原始錄音 CAF（仍 cap ≤30s 讀取）。短檔才會被 iOS 完整播。
2. **新增 `scheduleGentleRepeatBurst`**：對「下一次發生」加排數顆秒級錯開的一次性 Time-Sensitive 通知（`{uuid}-rep-k`），每顆播一段完整語音，串成約 30 秒後沒有更多通知 → 自然停（維持溫和、不續電）。兩顆通知的間距 = 一段語音長度 + `recordingGapSeconds`（沿用設定頁既有的 Stepper，預設 2 秒、可調）。
3. **保留 baseline**：每個 weekday 仍排 1 顆 repeating 通知，即使被殺多天沒開 App，至少還會響一段完整語音（比舊的 2 秒好）。burst 只鋪下一次發生，每次 re-arm 重排。
4. **64 pending 上限防衛**：用 runtime `pendingNotificationRequests().count` 動態計算剩餘額度，鬧鐘多時自動少排、不會爆。
5. **反向自我修復**：偵測到既有 CAF ≥25 秒（舊版 loop 成 ~29s 的檔）就用原始錄音重匯出成短檔並更新鬧鐘，讓既有鬧鐘自動痊癒、免使用者一顆顆重選。新短檔 < 25 秒後不再觸發（idempotent）。
6. `{uuid}-rep-k` 一併納入排程頂部清掃、`cancel`、`cancelNags`（App 為該鬧鐘開起＝小孩醒了，停掉後續語音）。

## 其他改動

在鬧鐘編輯頁「啟用口令關閉」下方加一行警語「口令關閉需保持螢幕開啟，不可關屏。」（中英各自獨立字串，避免英文版掉回中文）。原因：口令關閉靠麥克風即時辨識，只在前景／亮屏有效；關屏或殺 App 走的是這套自動停的提醒模式，沒有麥克風可聽口令。

## 驗證

真機 pass。Log 出現 `gentle-repeat burst → 4 extra slot(s), every 7s over ~30s (voice=4.6s gap=2s)`，且 `pending=8` 內含 baseline（`-1`、`-7`）加上 `rep-1`～`rep-4`。殺 App、關屏下聽到人聲重複約 30 秒後自然停止。

## DEBUG 工具（不進 release）

為了量測 iOS 自訂音「完整播放」的真實上限，加了一個 cutoff probe：設定頁的「🔬 DEBUG」紅色按鈕一按，會排 5 顆一次性通知（now+1～+5 分），長度分別 8／12／16／20／24 秒、內容是「每秒一聲嗶、5 的倍數高音」的尺規音。殺 App＋關屏逐顆聽，數嗶聲就知道哪個長度被截。整套包在 `#if DEBUG`，App Store archive 不會含這段。

## 待辦

1. 跑 cutoff probe，找出 iOS 在 4.6～29 秒之間的真實截斷點。
2. 拿到截斷點後處理 **≥30s 錄音**：app 自動把通知用片段切到截斷點以下，並在錄音頁提示使用者「超過 X 秒的部分鎖屏提醒只播前段並重複」。
3. 小雷：鬧鐘編輯頁「啟用口令關閉」那顆 Label 用的 `mic.badge.checkmark` 在實機 log 報 `No symbol named`，是無效 SF Symbol，待換。

## 異動檔案

`Services/AudioRecorder.swift`、`Services/AlarmScheduler.swift`、`Views/Settings/AlarmEditorView.swift`、`Localizable.xcstrings`、`Views/Home/HomeView.swift`。

## 備註：commit 環境問題

這次在沙箱環境 commit，掛載的 `.git` 不允許刪檔，導致殘留 stale lock，且真正的 `.git/index` 沒同步（`git status` 會誤顯示檔案 `MM`，但 commit 本身完整、`HEAD` 與 `dev/auto` 都指向 `b2e0b01`）。在 Mac Terminal 清理：

```
cd ~/Documents/SunnyWalker
./remove_git_lock.sh && rm -f .git/objects/maintenance.lock && git reset
```

Archive 出版前記得照慣例先跑 `xcodegen generate`。
