# SunnyWalker Stability & Performance Review

檢查日期：2026-07-24  
檢查範圍：`SunnyWalker/`、`SunnyWalkerTests/`、`project.yml`、`scripts/validate.sh`  
檢查基準：`/Users/lion/Documents/02.all_project_info/98.validation_performance.md`

## 結論

以指定 simulator UUID 執行 `xcodebuild build test` 成功，現有測試全數通過；但仍有 3 項 P1、5 項 P2。最高風險集中在錄音頁離場清理、背景麥克風啟動失敗後的資源回收，以及「所有辨識皆在裝置端」的隱私宣告與實作不一致。

## P1

### 1. 錄音 sheet 可被下滑關閉，但沒有離場清理，麥克風與 Timer 可能繼續運作

- 證據：
  - `VoiceLibraryView.swift:130-134` 以一般 `.sheet` 顯示 `VoiceClipRecorderSheet`，沒有禁止互動式關閉。
  - `VoiceClipRecorderSheet` 的 `body`（`VoiceLibraryView.swift:456-493`）沒有 `.onDisappear`。
  - 倒數 Timer 由 `@State` 持有，closure 又捕捉 `self`（`VoiceLibraryView.swift:830-843`）。
  - 只有按「取消」才會執行 `cancelAndDismiss()` 的 Timer、播放器、語音辨識與錄音清理（`VoiceLibraryView.swift:859-864`）。
- 影響：使用者錄音中直接下滑關閉 sheet 時，錄音可能持續到上限，橘色麥克風指示與耗電持續；Timer/State 捕捉鏈也會延長整個錄音畫面的生命週期，並可能留下非預期錄音檔。
- 建議：在 sheet 根視圖加冪等的 `.onDisappear` cleanup（invalidate Timer、cancel speech、stop player、`await recorder.stop()`，並依產品規則保存或刪除未完成 take）；或錄音期間使用 `.interactiveDismissDisabled(true)`，但仍應保留離場清理作最後保險。

### 2. 背景聆聽啟動失敗後沒有 rollback，再次啟動可能因重複 installTap 而 crash

- 證據：
  - `BackgroundListeningManager.start()` 先啟用 audio session，再於 input bus 安裝 tap（`AudioRecorder.swift:205-220`）。
  - `engine.start()` 若丟錯，catch 只印 log（`AudioRecorder.swift:221-247`），沒有 removeTap、stop engine 或 deactivate session。
  - `stop()` 一開始以 `isActive` guard（`AudioRecorder.swift:250-263`）；失敗路徑尚未把 `isActive` 設成 true，因此外部呼叫 `stop()` 也無法清理。
- 影響：第一次啟動失敗後殘留 tap/audio session；下一次 `start()` 對同一 bus 再 `installTap`，可能觸發 AVAudioEngine Objective-C precondition crash。失敗後也可能殘留錄音 session、持續占用系統音訊資源。
- 建議：把「session 已取得／tap 已安裝」分別記錄，所有 guard/catch 走同一個 rollback；`stop()` 不應只依賴 `isActive` 才釋放部分初始化資源。加入「engine.start 失敗後可安全重試」測試。

### 3. 自動命名可能使用伺服器辨識，與 Info.plist 的純裝置端隱私宣告矛盾

- 證據：
  - `Info.plist:27-30` 宣告「聲音只留在這台 iPhone 裡，不會傳出去」及「所有辨識都在這台裝置上完成」。
  - 錄音自動命名只有在 `supportsOnDeviceRecognition == true` 時才設定 `requiresOnDeviceRecognition = true`；不支援時仍照常建立 recognition task（`VoiceLibraryView.swift:786-804`）。
- 影響：不支援離線辨識的裝置/語系可能退回 Apple server speech recognition，與對家長及 App Review 的明確隱私承諾不一致；本 App 又屬兒童情境，風險更高。
- 建議：自動命名也應像 `SpeechRecognizer.startListening()` 一樣，先 guard `supportsOnDeviceRecognition`，並無條件設定 `requiresOnDeviceRecognition = true`；不支援時顯示本地化提示，不要建立辨識 task。

## P2

### 4. CAF 轉檔在 MainActor 同步讀寫，可能造成 UI 無回應

- 證據：
  - `AlarmScheduler` 整個類別是 `@MainActor`（`AlarmScheduler.swift:10-16`）。
  - `schedule()` 會同步呼叫 `AlarmSoundExporter`（`AlarmScheduler.swift:65-68`、`125-130`、`146-150`）。
  - exporter 同步配置最多 30 秒 PCM buffer、讀完整音訊並寫 CAF（`AudioRecorder.swift:475-512`）；`RecordingView.swift:200-215` 也從 UI Task 直接呼叫。
- 影響：長錄音轉檔、檔案系統較慢或裝置負載高時，主執行緒可能出現可感卡頓；儲存鬧鐘與離開錄音頁尤其明顯。
- 建議：把純檔案／音訊轉檔移到非 MainActor 的 async service，完成後才回 MainActor 更新 `Alarm` 與畫面狀態；加入 signpost 或效能測試量測 30 秒輸入。

### 5. 背景語音辨識錯誤會零延遲無上限重啟

- 證據：`AudioRecorder.swift:397-436` 在每個 recognition error 都立即 `restartRecognition()`，沒有 backoff、重試上限，也沒有先檢查 `supportsOnDeviceRecognition`。
- 影響：持續性錯誤（離線模型不可用、權限/route 異常）會形成快速 cancel/create loop，增加 CPU、電量與 log 壓力。此功能目前標示 experimental/off by default，但啟用後風險存在。
- 建議：先檢查離線能力；採有限次數 exponential backoff，超限後停止 firing recognition 並提供可恢復狀態。

### 6. Swift 6 actor isolation warning 尚未處理

- 證據：實際 build 對 `LocalizationManager: ObservableObject`（`Localization.swift:48-60`）警告 actor-isolated conformance crossing，並明示在 Swift 6 language mode 會成為 error。
- 影響：目前 Swift 5.9 可編譯，但升級 Swift 6 時會阻擋 build，且警告指出潛在 data race 邊界。
- 建議：依 compiler 建議隔離 conformance，或改用與目前 SDK 相容的 Observation/`@Published` 實作；在 CI 增加 Swift 6 migration build。

### 7. 結構過度集中，且 SwiftLint 基線未收斂

- 證據：
  - `VoiceLibraryView.swift` 1,411 行、`HomeView.swift` 1,096 行、`AudioRecorder.swift` 650 行；UI、音訊轉檔、背景聆聽、資料處理混在同檔。
  - 對 `SunnyWalker` 與 `SunnyWalkerTests` 精準執行 SwiftLint，共 275 項（107 errors、168 warnings）；主要為 `identifier_name` 110、`line_length` 84、`file_length` 11。
- 影響：高風險音訊生命週期難以單元測試，改動容易跨功能互相影響；lint 噪音過高也使新增 regression 難以被看見。
- 建議：先建立專案認可的 `.swiftlint.yml` 與 baseline，再逐步拆出 `VoiceRecorderCoordinator`、`AlarmSoundExporter`、`BackgroundListeningManager` 及 Home 子畫面；CI 只阻擋新增違規，再逐批清舊債。

### 8. `scripts/validate.sh` 會誤報 build 失敗，且 lint 範圍不穩定

- 證據：
  - simulator 偵測只保留名稱（`scripts/validate.sh:13-18`）。本機同時存在 iPhone 17 Pro Max / iOS 26.2，而 `name=` destination 被解析成 `OS:latest`，實跑得到 exit 70「Unable to find a device」；改用該 simulator UUID 後 build/test 成功。
  - script 直接 tee 到未建立的日期目錄（`scripts/validate.sh:60`、`77`、`86`），本次三處皆出現 `No such file or directory`。
  - `swiftlint --quiet` 未限定路徑或 excludes（`scripts/validate.sh:83-87`），會把 `.build` 的第三方 package 與旁支 `KidBrowser` 一起掃入。
- 影響：CI/agent 可能把環境問題誤判成 App build regression，也無法保留 build/test log；lint 結果會隨 `.build` 是否存在而改變。
- 建議：由 `simctl --json` 選一個 available UDID 並用 `id=`；先 `mkdir -p` 當日日誌目錄；SwiftLint 明確限定 `SunnyWalker SunnyWalkerTests`，並排除 `.build`/第三方來源。

## 其他警告

- `UIRequiresFullScreen` 在 iOS 26 已 deprecated；build 成功但每次 build/test 各產生一次 warning。應追蹤替代的 iPad/方向策略，避免未來 SDK 忽略後造成版面或 App Store 設定落差。
- App runtime source 未找到 `try!`／`as!`；三個 `.min()!` 前都有非空 guard/filter 條件。`AlarmListView.swift:277` 的 `try! ModelContainer` 位於 `#Preview`，不影響正式 App，但會讓 Preview 在 schema/config 錯誤時直接 crash。
- 未發現 hardcoded token/password；目前 UserDefaults 內容為設定、鬧鐘生命週期與非敏感識別資料，未看到把憑證存入 UserDefaults。

## 驗證紀錄

1. `./scripts/validate.sh`
   - pbxproj registration：pass
   - build：fail（exit 70，錯誤 destination；屬驗證腳本問題）
   - test：skipped
   - lint：fail（exit 2，且混入 `.build`/旁支來源）
2. 修正 destination 後執行：
   - `xcodebuild -scheme SunnyWalker -destination 'platform=iOS Simulator,id=040573F6-7A5F-4B20-A1FE-22686A962B63' -derivedDataPath .build/verified -quiet build test`
   - 結果：exit 0，build 成功、tests 成功
   - warnings：`LocalizationManager` actor conformance、`UIRequiresFullScreen` deprecated
3. `swiftlint lint --quiet --reporter json SunnyWalker SunnyWalkerTests`
   - 275 項：107 errors、168 warnings

## 建議處理順序

1. 先修 P1-1、P1-2、P1-3，補錄音離場、失敗後重試及純離線辨識測試。
2. 修 `validate.sh`，讓後續每次修正都能取得可信 build/test/lint 結果。
3. 移出 MainActor 的 CAF 轉檔與辨識重試節流。
4. 建立 SwiftLint baseline，再分拆大型檔案與處理 Swift 6 warning。
