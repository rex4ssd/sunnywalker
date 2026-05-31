# SunnyWalker v2 — 分階段開發計畫

> 搭配 `DESIGN_v2.md`。目標：從現有 v1（UNUserNotificationCenter 版）漸進重構到 AlarmKit 混合架構。
> 每個階段都有明確的「驗收標準」，做完才進下一階段。

---

## 階段總覽

| 階段 | 主題 | 產出 | 預估 |
|---|---|---|---|
| P0 | 地基切換：AlarmKit PoC | 能在鎖屏 + 靜音下響的鬧鐘 | 必做、最優先 |
| P1 | 混合流程串接 | 響鈴 → App Intent → 互動畫面 | 核心 |
| P2 | 鬧鐘＝聲音＋任務 | 任務卡 + 家長錄音解耦 | 核心 |
| P3 | 小孩端 UI / 互動關鬧鐘 | 零文字可操作的可愛流程 | 差異化 |
| P4 | 床邊模式 + 省電 | 暗屏待機、響鈴亮、響完關 | 對應痛點 |
| P5 | 家長區 + 起床紀錄 + 鎖 | 設定/紀錄/獎勵 | 完整度 |
| P6 | 商業模式 + 上架 | freemium、隱私合規、App Store | 變現 |

---

## P0 — 地基切換：AlarmKit PoC（最優先）

**為什麼先做**：這是整個 v2 成立與否的前提。如果 AlarmKit 在你的目標裝置上行為不如預期，後面都要調整，所以先用最小可行驗證。

任務：
1. 專案最低版本設 **iOS 26**；`Info.plist` 加 `NSAlarmKitUsageDescription`。
2. 新增 `Services/AlarmKitService.swift`：封裝 `requestAuthorization()` 與 `schedule(id:configuration:)`。
3. 排一個 1 分鐘後、單次的鬧鐘，bundle 內放一個 `.caf` 叫醒聲。
4. **保留 v1 的 `AlarmScheduler`（UNUserNotificationCenter）暫時不刪**，待 P1 確認後再移除。

驗收標準：
- [ ] 裝置**鎖屏**時鬧鐘會全螢幕響起。
- [ ] 裝置在**靜音 / 專注模式**下仍會響。
- [ ] 不按時，系統 UI **會自動超時結束**（驗證省電前提）。
- [ ] 按下 stop 按鈕能正常停止。

---

## P1 — 混合流程串接

任務：
1. 為 stop 按鈕綁 **App Intent**，被按下時把 App 帶到前景並導向「起床任務」畫面。
2. 用 `AlarmAttributes` 的 metadata 帶上 `alarmID`，讓 App 知道是哪個鬧鐘被觸發。
3. App 進前景後，依 `alarmID` 找到對應鬧鐘 → 進 `AlarmRingView`（互動畫面）。
4. 移除 v1 `AlarmScheduler` 對排程的依賴（功能由 AlarmKit 取代）。

驗收標準：
- [ ] 鎖屏響鈴 → 按「我起床了」→ App 開啟並停在正確鬧鐘的互動畫面。
- [ ] 重複鬧鐘（每週）排程正確，跨日 / 跨時區不跑掉。
- [ ] 舊的通知排程已停用，沒有重複響鈴。

---

## P2 — 鬧鐘＝聲音＋任務

任務：
1. `Alarm` 模型加 `taskType`、`voiceClipID`、`alarmKitID`（見 DESIGN §7）。
2. `VoiceClip` 與 `Alarm` **解耦**：錄音用獨立 id 命名，可被多個鬧鐘共用（修掉 v1 用 `alarm.id` 當檔名的限制）。
3. 互動畫面播放 `Documents/Recordings/` 的家長錄音（可循環、不受 AlarmKit 聲音限制）。
4. 內建任務模板（上學/睡覺/刷牙/午睡…）與對應大圖示。
5. 更新 Markdown 匯入匯出格式，加任務欄位：`weekdays, 07:30, 上學, school`。

驗收標準：
- [ ] 一段錄音可指派給多個鬧鐘。
- [ ] 互動畫面正確播放對應錄音 + 顯示任務卡。
- [ ] Markdown 匯入含任務類型可正確還原。
- [ ] 錄音規格符合壓縮建議（單聲道、低位元率）。

---

## P3 — 小孩端 UI / 互動關鬧鐘

任務：
1. 小孩首頁：滿版時間天空場景 + 龍貓 + 下一個鬧鐘大圖示（無列表、無設定鈕）。
2. 響鈴互動畫面：龍貓動畫 + 任務圖示 + 一顆主按鈕，**零文字可懂**。
3. 完成獎勵動畫（貼紙 / 集點）。
4. （可選）家長可開啟「說『我起床了』才能關」的語音關卡（`SFSpeechRecognizer` 離線、僅前景）。
5. 全畫面加語音輔助 / 大圖示 / 高對比。

驗收標準：
- [ ] 找一位 3–6 歲兒童實測：不靠文字能自己完成關鬧鐘。
- [ ] 互動流程每畫面只有一個主要動作。
- [ ] 語音關卡開啟時，辨識到關鍵詞才結束。

---

## P4 — 床邊模式 + 省電

任務：
1. 床邊模式：平常極暗夜間時鐘（深色、低亮度、睡著的龍貓）。
2. `isIdleTimerDisabled` 僅在響鈴互動期間為 true，結束立即還原。
3. 整合 iOS 26 StandBy / Live Activity 呈現（插電當床頭鐘）。
4. 完成任務後自動降亮度 / 退出全亮。

驗收標準：
- [ ] 床邊模式整夜不會維持高亮度（量測耗電明顯低於內建「響不停」情境）。
- [ ] 響鈴亮、響完（或完成任務）即恢復暗屏。

---

## P5 — 家長區 + 起床紀錄 + 鎖

任務：
1. 家長區入口加「長按 + 數字/手勢鎖」，避免小孩誤入誤改。
2. `WakeRecord` 紀錄：起床時間、是否需第二次叫、連續天數。
3. 家長儀表板：本週起床概況、獎勵管理。
4. 鬧鐘列表 / 錄音 / 任務設定 / 匯入匯出 全收進家長區。

驗收標準：
- [ ] 小孩無法在沒有家長解鎖下更改鬧鐘。
- [ ] 起床紀錄正確累積並顯示。

---

## P6 — 商業模式 + 上架

任務：
1. freemium：免費版有限錄音數；付費解鎖私有雲端備份 / 同步 / 無限錄音 / 造型。
2. 自願投稿聲音庫（換獎勵），**兒童語音預設不公開**，內容審核管線。
3. 隱私合規：COPPA / GDPR-K、家長同意流程、資料最小化。
4. 雲端：壓縮上傳、egress 便宜的物件儲存、上限控管。
5. App Store 上架素材（兒童類別有額外審核要求，需留意）。

驗收標準：
- [ ] 付費牆與免費額度運作正常。
- [ ] 公開分享流程符合兒少隱私紅線（預設私有 + 審核）。
- [ ] 通過 App Store 兒童類別審核。

---

## 與現有程式碼的關係（給你銜接用）

- **沿用**：`GhibliColors/Fonts/Animations`、`TotoroAvatar`、`WatercolorCard`、`HomeView` 場景、`AudioRecorder`、`AudioPlayer`、`RewardView`。
- **改寫**：`AlarmScheduler`（→ `AlarmKitService`）、`Alarm` 模型（加欄位）、`VoiceClip` 命名解耦、`AlarmRingView`（改由 App Intent 進入、語音定位為加強關卡）。
- **新增**：`AlarmKitService`、App Intent、`taskType` 任務系統、`WakeRecord`、家長鎖、床邊模式。
- **已完成**：`MarkdownAlarmIO` + `AlarmIOView`（P2 再加任務欄位）。
