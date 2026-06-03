# Session 回顧：踩雷 & 無效的 implement（2026-06-03）

> 接手自斷掉的 `sunnay_0603`，處理鬧鐘自訂聲音、聲控、背景聲控、貪睡模式、icon。
> 這份只記**踩到的雷**和**做了卻沒效的實作**，給下個 session 少走冤枉路。完整變更看
> `docs/fix_report_2026-06-03_three_alarm_bugs.md` 與 `docs/design_background_voice_stop.md`。

---

## ❌ 無效 / 白做的 implement

### 1. 第一輪改 AlarmKit 側的自訂聲音，完全沒效（最大教訓）
- **做了什麼**：在 `AlarmKitService` 把 `sound: .named(soundFileName)` 指到匯出的 caf、加 `cancel` 再 `schedule`。
- **為什麼沒效**：這台真機 **AlarmKit entitlement 還沒批** → `requestAuthorization()` 失敗 → `isAuthorized=false` → AlarmKit 整條是 dormant 的。真正在響的是 `AlarmScheduler`（UNNotification 舊路徑）。改 AlarmKit 等於改一條沒在跑的路。
- **正解**：改 `AlarmScheduler` 的 `content.sound`（它本來寫死 `.default`）。
- **教訓**：🔴 **動手修之前，先確認「現在到底走哪條路徑」**。看是全螢幕鬧鐘還是黑色通知橫幅、看 `AlarmKitAuthorized=` log。一個 isAuthorized 的判斷就決定改哪邊，賭錯整輪白做。

### 2. 一開始斷言「背景不能開麥克風」——講錯了
- **錯在哪**：說得太絕對。Apple 實際限制是「**背景只能延續前景啟動的 session，不能從背景啟動**」。recorder app 能整夜錄，是因為使用者在前景就按了開始錄。
- **修正**：查證 Apple 文件後改口，並據此做了 Tier2 背景聆聽（前景啟 session → 背景保活）。
- **教訓**：🟡 平台能力的「不可能」要先查證再講，別憑印象。

### 3. 加的 log 自己造成 compile error
- `print(... recognizer.locale?.identifier ...)` — `SFSpeechRecognizer.locale` 是**非 optional** 的 `Locale`，`?.` 直接編譯失敗。
- **教訓**：🟡 加 debug log 也要顧型別；optional chaining 用在非 optional 上會擋掉整個 build。

---

## ⚠️ 踩到的雷（root cause）

1. **AudioPlayer gap-loop 每次重播都重設 AVAudioSession 為 `.playback`** → 把 `SpeechRecognizer` 的 `.playAndRecord` 麥克風打掉，錄音一 loop（幾秒後）聲控就死 → 「聲控失效」。修法：session 只在 `play()` 設一次，loop 只重建 player。

2. **AlarmKit 不會 re-arm 已 fired+stopped 的 id**：terminal 狀態下用同 id `schedule()` 被靜默忽略 →「鬧鐘叫完往後調就不響」。修法：schedule 前先 `cancel(id:)`。

3. **背景喚醒路由會漏**：`onAppear` 只跑一次、`NotificationCenter.post` 是 ephemeral，app 從鎖屏背景回前景時 post 會丟 →「解鎖鐘就停」。修法：UserDefaults marker + `scenePhase==.active` 重新路由 + `@Query` load 後重試。

4. **`UNNotificationSound(named:)` 靜默 fallback**：檔案不存在 / 格式錯 / >30s 會無聲退回預設音，**不報錯**，最難查。修法：排程當下用 `FileManager` 驗 caf 存在才用，並 print Library/Sounds 內容；匯出 caf 限 mono 16-bit PCM ≤30s。

5. **新 .swift 檔常常沒進 Xcode target**（前幾個 session 的舊雷）：本回合所有新功能（含 `BackgroundListeningManager`）一律塞進**既有檔案**，完全避開這個雷。

6. **雙 AVAudioEngine 搶 input node**：背景聆聽的 engine 與 AlarmRingView 的 SpeechRecognizer 若同時跑會打架。用 `applicationState != .active` gate + `firingAlarm` 出現時 stop manager 來避開。

---

## 🧪 還沒在真機驗證 / 已知 caveat
- 背景聆聽（Tier2）橘點整夜長亮 → **兒童 App 上架審核最大風險**（非技術）。預設關。
- 背景聆聽自響時 UNNotification 也會響 → 雙聲源；錄音時要先關背景聆聽（engine 打架）。
- 貪睡模式 nag：重複鬧鐘只排「下次發生」，靠下次開 App re-arm 續期。
- 自訂 caf 若在少數裝置仍 fallback 成靜音 → 退路是改成「直接錄 caf」而非 m4a→caf 轉檔。
- iOS app 無法在這個環境編譯，所有 Swift 改動都是人工核對，**需真機驗證**。
