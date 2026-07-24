
其實有個好消息：**iOS 的本地通知（Local Notification）自訂音效長度上限是 30 秒，而不是 2 秒！**

你可能聽說過 2 秒的說法，或者之前測試時發現聲音出不來，這是因為如果音檔不符合蘋果的規範，系統就會直接沒收你的音效，強制改播預設的短短「叮」一聲。

一句「哥哥要休息十分鐘囉」的錄音大概只需要 3 到 5 秒，所以利用推播來播放這段語音是完全可行的，空間綽綽有餘。

## 確保推播能播放長音效的 3 個鐵則

要讓系統乖乖播完你的錄音，必須嚴格遵守以下條件：

* **格式必須正確：** 蘋果的推播音效只接受 `.wav`、`.aiff` 或 `.caf` 格式（不支援常見的 `.mp3` 或 `.m4a`）。強烈建議轉換成 `.caf`，你可以直接打開 Mac 的「終端機 (Terminal)」輸入指令秒轉：
`afconvert -f caff -d ima4 你的原檔.mp3 轉換後.caf`
* **檔案放對位置：** 把轉好的音檔（例如 `brother_rest.caf`）拖進 Xcode 專案目錄下。務必確認右側面板的 **Target Membership** 有打勾，確保這個音檔有被打包進 App 裡（Copy Bundle Resources）。
* **絕對不能超過 30 秒：** 如果你的檔案是 30.1 秒，系統會判定無效並強制退回預設音效。

## 程式碼設定方式

在你的 `DeviceActivityMonitor` 觸發休息時間時，順便呼叫這段推播程式碼：

```swift
import UserNotifications

func scheduleBreakNotification() {
    let content = UNMutableNotificationContent()
    content.title = "休息時間到！"
    content.body = "眼睛要休息 10 分鐘囉！"
    
    // 這裡填入你的錄音檔名，包含副檔名
    content.sound = UNNotificationSound(named: UNNotificationSoundName("brother_rest.caf"))
    
    // 設定 1 秒後立刻觸發推播
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: "BreakTime", content: content, trigger: trigger)
    
    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("推播設定失敗：\(error.localizedDescription)")
        }
    }
}

```

> **關鍵機制提醒：** iOS 的預設行為是「當 App 在前景開啟時，推播不會跳出，也沒有聲音」。但由於你是利用 Screen Time API 在背景監控，30 分鐘一到時，小孩一定是在玩別的遊戲或看影片（你的 App 在背景），所以推播和錄音一定會正常彈出並播放。


