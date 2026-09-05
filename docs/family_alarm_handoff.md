# 家族 app → SunnyWalker 鬧鐘／提醒 交接（規劃 + 已落地的地基）

> 2026-09-03。對應 todo「未來會預計會有家族 iOS app 登入的功能，會透過其它 app 傳送時間過來
> sunnywalker，變成鬧鐘、或是提醒」。

## 一句話

**外部 app 只能「提議」，SunnyWalker 家長按「加入」才建。** 不管之後接的是 URL scheme、
App Group、CloudKit 還是家族登入，資料契約都是 `FamilyAlarmRequest`，畫面都是
`FamilyAlarmRequestSheet`，家長閘與上限檢查都在 `HomeView.requestAddFamilyAlarm`。
換傳輸層不用重寫流程。

## 已落地（本次）

| 件 | 位置 |
|---|---|
| 資料契約 `FamilyAlarmRequest`（parse / makeURL / makeAlarm） | `SunnyWalker/Services/FamilyAlarmRequest.swift` |
| 預覽頁（時刻、標籤、星期、種類、來源 app） | `SunnyWalker/Views/Settings/FamilyAlarmRequestSheet.swift` |
| 入口 `.onOpenURL` + 家長閘 + 上限 + 建鬧鐘 | `HomeView.swift`（`requestAddFamilyAlarm` / `addFamilyAlarm`） |
| URL scheme `rexsunny`（早已宣告，之前沒人接） | `project.yml` → Info.plist `CFBundleURLTypes` |
| 單元測試（parse / 預設值 / 壞輸入 / round-trip） | `SunnyWalkerTests/ChimeIntervalTests.swift` |

### URL 格式

```
rexsunny://alarm?time=07:30&label=上學囉&days=2,3,4,5,6&kind=alarm&from=LetAbacus
```

| 參數 | 必填 | 說明 |
|---|---|---|
| `time` | ✅ | `HH:MM` 24 小時制 |
| `label` | – | 標籤（URL-encoded，最多 40 字） |
| `days` | – | `1`=日 … `7`=六，逗號分隔；省略＝週一到週五 |
| `kind` | – | `alarm`（預設）／`chime`（報時）／`todo`（待辦） |
| `from` | – | 來源 app 顯示名，只用於「由 ○○ 傳來」 |

其他家族 app 端（Swift）：

```swift
var c = URLComponents(string: "rexsunny://alarm")!
c.queryItems = [.init(name: "time", value: "07:30"),
                .init(name: "label", value: "上學囉"),
                .init(name: "from", value: "LetAbacus")]
if let url = c.url, UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
```
（呼叫端 Info.plist 要加 `LSApplicationQueriesSchemes: [rexsunny]` 才能 `canOpenURL`。）

### 種類與群組的對應

* `chime` → 找第一個開了「報時」的群組；沒有就退成一般鬧鐘。
* `todo` → 找第一個開了「待辦」的群組；建好後直接開編輯器讓家長補錄提醒語音（待辦沒錄音不能存）；
  沒有待辦群組就退成一般鬧鐘。
* `alarm` → 放進首頁目前顯示的那一組。

### 安全邊界（Made for Kids）

* 只預覽、不自動建；加入要過家長閘（解鎖窗內免問，跟「＋」一樣）。
* 免費版 10 顆上限照擋。
* 不接受任何會開網頁／導向外部的欄位；`from` 只是顯示字串。

## 下一步（未做，依成本排序）

1. **App Group 共用容器**（零後端、同裝置）：家族 app 寫一個 `pending_alarms.json` 到
   `group.app.rexcode.family`，SunnyWalker 回前景時讀取 → 同一個預覽頁。適合「LetAbacus 練完
   自動幫孩子排明天複習提醒」這種同機情境。改動：`FamilyAlarmRequest` 加 `Codable`、HomeView
   多一個讀檔入口。
2. **CloudKit 共享（跨裝置，家長手機 → 孩子 iPad）**：Vein 已有結論——Kids Category 下 iCloud
   同步仍算 user data 離機，隱私問卷要重過一次；建議做成 Pro 功能、且只同步「鬧鐘設定」不同步錄音。
3. **家族登入**：在 1/2 之上加身分，目前家族沒有任何後端，不建議為此起後端；用 iCloud 帳號
   （CloudKit 的 owner）當身分即可。
