# 03_todo_fectures，完成後加 `done-YYYYMMDD_HHMM` 搬到 ## complete, fetures。


#  to do task,  add voice, time settin by line msg
-大人透過line或區網更新daily jobs,每晚訂時提醒小孩去做 
主畫面上方出現氣球或太陽，表示有todo，點開用語音問job1、2是否完成(或用ui 讓kid點)都完成，氣球會消失，會有每周完成事頁紀錄和評平

#

## 聲音時光機, 時空膠囊語音 (Voice Time Capsule)
為了讓這個功能更穩定且具有吸引力，建議採取以下實作策略：

在地化排程 (Local Scheduling)： 透過 iOS 的 UNUserNotificationCenter 結合本機時間判斷，即可在指定日期播放音檔，這完全不需要後端伺服器運算，能最大化節能與隱私。

視覺化介面： 在 App 內做一個「時空信箱」的 UI，讓孩子看到自己存了多少則「未來的訊息」。這能提高 App 的使用黏著度，家長也會因為這些珍貴的成長紀錄而更願意付費支持。

### Future（原筆記項目的定位建議）
- 時空膠囊語音 → 最適合當 Pro 招牌功能，local scheduling 免後端，優先做
- 小孩錄音 CloudKit 家庭同步 → Pro v2；Kids Category 隱私要再過一次合規（iCloud 同步仍算 user data 離機）
- Line 設定語音/時間 → 需後端＋第三方，Made for Kids 幾乎無法過審，放最後或放棄
- 成長聲音自動剪輯 → Pro 加值好題材，純 on-device 可行



# 小孩錄音功能
技術架構與隱私策略 (CloudKit 是首選)
這項功能意味著 App 需要跨裝置同步（從小孩的設備傳到家長的手機）。

零伺服器成本與高隱私： 強烈建議採用 Apple 的 CloudKit 來實作。將錄音檔直接同步到用戶家庭群組的 iCloud 空間。這樣不僅能省下您建置後端伺服器與儲存空間的成本，資料完全掌握在使用者手裡，更能完美解決兒童隱私與資安合規的問題。


#將聲音在app 自動剪輯成長聲音記錄的音檔

#睡前的床邊故事



## -----------
## complete






-----------------------------------------------------------------
## complete, fetures


-----------------------------------------------------------------
## 深色模式對比掃描（2026-07-11）— 幾乎全 false positive
SunnyWalker 是 adaptive（沒鎖 light/dark，跟系統）。`darkmode_validate.py`（`py cmd_entry.py 19`）
掃到 5 ERROR + 1 WARN，逐一黑底複核：
- **吉祥物眼白（勿改）**：`GiraffeAvatar.swift:171`、`SunnyAvatar.swift:57`、`MascotView.swift:351/436`
  的 `Circle().fill(Color.white)` 是角色眼白（上面疊 `ink` 瞳孔），兩個模式都該是白 → 正確。
- **low priority**：`VoiceLibraryView.swift:576` 錄音命名卡 `.background(Color.white)` 配 `nightIndigo`
  （固定深）文字 → 深色模式仍可讀（深字白底），只是白卡在深色 UI 偏亮、不一致。要一致可換 adaptive 卡色（設計取捨，非 bug）。
- **verify**：`KidBrowser/HomeView.swift:136` `.background(Color(hex:"#FFD8A8"))` peach 裝飾底 → 確認上面文字對比即可。
結論：無「黑底看不見」的真雷，本批不改 code。
