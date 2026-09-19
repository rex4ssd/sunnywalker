# App Store Connect 內容 — 1.4.20260920 (build 18)

> 每格中（zh-Hant）／英（en）兩版；**fence 內＝要進 ASC 的值，一律不得有 emoji**。
> 用 `asc_push.py` 推，不手貼（`common_lib_ios/docs/asc_automation.md`）。
> 前一份 `appstoreconnect_content_260814.md`（1.4.20260814，從未送審）已標記作廢，本檔是它的超集。
>
> 本 app 的退件教訓（寫文案前先讀）
> 1. **4.1**：不得提第三方品牌（2026-06-18 副標題被退）。
> 2. **2.3**：只寫已實作並驗證過的功能。
> 3. **2.3.7**：Name／Subtitle／Promotional Text／Keywords **不得出現價格字眼，連「免費 free」都算**
>    （260814 那份的 Promo 就是卡在這條，這版已改寫）。
> 4. **2.3.8**：出現「兒童」字樣 → App 必須是 Kids 分類（本 app 是）。
>
> 沿用不動：App Name、Subtitle、Keywords、Description、Age Rating、App Privacy、Privacy Policy URL。
> **本次更新：What's New、Promotional Text、Review Notes、截圖。**

---

## What's New in This Version

**zh-Hant**

```
一台手機，全家小朋友各自的鬧鐘

多人鬧鐘
- 可分成哥哥、妹妹…各自的鬧鐘清單，首頁左右滑就能切換
- 每位小朋友可以有自己的吉祥物；新的「向日葵」吉祥物可以把你喜歡的照片放進花心
- 點一下首頁的群組名稱，就能把某位小朋友的鬧鐘整組暫停（需家長驗證），不會刪除任何設定

報時與倒數
- 報時鬧鐘：時間到用語音念出現在幾點，可選女聲或男聲、可試聽
- 區間報時：例如早上 7:00 到 7:30 每 5 分鐘報一次，催小朋友吃早餐、準備出門
- 倒數報時：改念「剩 30 分鐘、剩 20 分鐘、剩 10 分鐘」，離出門還有多久一聽就懂
- 語音跟著 App 語言（中文／英文）

待辦語音提醒
- 錄一句提醒、挑一個可愛圖示，時間到在主頁冒出來，孩子點一下就能聽，聽完長按確認收起
- 家長可在「待辦紀錄」看到孩子已接收

鬧鐘多了也不亂
- 卡片一眼分得出鬧鐘、報時、待辦，並標出今天「下一個」會響的是哪一顆
- 首頁排列可選：依時間、重複週期合併、依時段（早上／上午／下午／晚上）、依星期；點一下吉祥物就能切換
- 設定頁把少用的選項收進「進階設定」，新增鬧鐘頁更精簡

其他
- 免費版可設定的數量從 6 個提升到 10 個（鬧鐘與待辦合計）
- 修正：更新 App 之後，自訂鈴聲可能變成系統提示音
- 選擇錄音、錄音頁面更順，修正偶發的閃退
- 家長驗證可改用 4 位數密碼
- 修正中文介面下部分文字顯示成英文
- 支援動態字級與旁白（VoiceOver）朗讀修正

基本的叫醒功能永遠免費。完全離線、零廣告、不收集任何資料。
```

**en**

```
One phone, a separate set of alarms for each child

GROUPS
- Split alarms per child (Brother, Sister, and so on) and swipe left or right on the home screen to switch
- Each child can have their own mascot. The new Sunflower mascot lets you drop your own photo into the flower's center
- Tap a group's name on the home screen to pause that child's whole set of alarms (parent check required). Nothing is deleted

TIME CHIME AND COUNTDOWN
- Time chime: at the set time the alarm speaks the current time out loud. Choose a female or male voice and preview it
- Repeat until an end time: for example every 5 minutes from 7:00 to 7:30, to keep breakfast and getting out the door on track
- Countdown: announces "30 minutes left, 20 minutes left, 10 minutes left" instead of the clock time
- The voice follows the app language (English or Chinese)

TO-DO VOICE REMINDERS
- Record a short reminder, pick a friendly icon, and it pops up on the home screen at the right time. Your child taps to listen, then presses and holds to confirm
- Parents can see what was received in the To-do log

TIDY EVEN WITH MANY ALARMS
- Cards now show at a glance whether an item is an alarm, a time chime or a to-do, and mark the next one to ring today
- Arrange the home list by time, merged repeats, time of day, or weekday. Tap the mascot to switch
- Rarely used options moved into Advanced settings, and the new-alarm page is shorter

ALSO
- The free limit goes from 6 to 10 items (alarms and to-dos combined)
- Fixed: after updating the app, a custom ringtone could fall back to the default system tone
- Smoother recording and ringtone screens, and a fix for an occasional crash
- The parent check can now use a 4-digit passcode
- Dynamic Type supported, plus VoiceOver reading fixes

Core wake-up features are always free. Fully offline, no ads, no data collection.
```

---

## Promotional Text

**zh-Hant**

```
一台手機，哥哥妹妹各自的鬧鐘清單與吉祥物。新增語音報時與「剩 10 分鐘」倒數提醒，催出門不用再用喊的。完全離線、零廣告、不收集資料。
```

**en**

```
One phone, a separate alarm list and mascot for each child. New spoken time chime and "10 minutes left" countdown for calmer mornings. Offline, no ads, no data.
```

---

## Review Notes（App Review Information → Notes）

```
SunnyWalker is a children's alarm clock. This update adds per-child alarm groups, a spoken time chime (with an optional repeat window and countdown), and to-do voice reminders. Everything runs on device.

1. Privacy: no accounts, no analytics, no third-party SDKs, no ads. Nothing the child records or the parent adds ever leaves the device. Recordings are stored in the app's own container and can be deleted in the app. Crash diagnostics delivered by the system (MetricKit) are only written to a local file inside the app container; the app has no networking code that sends them anywhere.

2. Parental gate: Settings, adding or editing an alarm, pausing a group, and the Pro purchase are all behind a parental gate. By default it is a three-digit multiplication question that children in the target age range cannot solve; a parent can switch it to a 4-digit passcode in Settings.

3. In-app purchase: SunnyWalker Pro is a one-time non-consumable that removes the limits of the standard version. It is offered only inside Settings, after the parental gate, and is handled entirely by StoreKit. The Pro row sits near the bottom of Settings, above "More from rexcode".

4. Time chime: the spoken time and the countdown phrases ("20 minutes left") are synthesized on device with the system speech synthesizer and delivered as local notifications. No network is involved.

5. Custom photo: the Sunflower mascot lets a parent place a photo in the flower's center using PhotosPicker, which runs out of process, so the app never requests photo library access and never reads the library itself.

6. To-do voice reminders: the parent records the reminder. The child only listens and confirms; no microphone access is needed for playback.

7. Family app shelf: Settings includes a "More from rexcode" shelf behind the parental gate. It lists only our own child-friendly apps. An App Store product page is shown with SKStoreProductViewController only after the gate. No third-party advertising, tracking, or external web content.

8. The "Rate us on the App Store" row is also inside Settings, behind the parental gate, and is never shown in the child's flow.
```

---

## 沿用欄位（本次不改，附此備查；asc_push 比對無差異就不會動）

### App Name

**zh-Hant**
```
SunnyWalker
```

**en**
```
SunnyWalker
```

### Subtitle

**zh-Hant**
```
暖聲喚醒的兒童小鬧鐘
```

**en**
```
Cozy Watercolor Kids Alarm
```

### Keywords

**zh-Hant**
```
兒童,鬧鐘,起床,賴床,小孩,親子,晨間,作息,習慣,語音,錄音,叫醒,幼兒園,國小,起床氣,提醒,早起,上學,媽媽,爸爸
```

**en**
```
kids,alarm,clock,wake,up,children,morning,routine,school,parent,voice,recording,gentle,child,habit
```

---

## 截圖（本版重拍）

`release_note/screenshots/v1.4.20260920/`：iPhone 6.9"（1320x2868）與 iPad 13"（2048x2732）各 5 張 x 中英；
`iphone65/` 是同一批縮成 1284x2778（架上原本只有 6.5" 那組，一起換掉才不會新舊混搭）。
畫面：首頁（依時段）／報時群組（區間＋倒數）／報時設定卡／新增鬧鐘／設定的群組段。
重拍：`scripts/shoot_store_shots.sh <UDID> <輸出資料夾> <iphone|ipad>`（DEBUG 的 StoreShots 模式灌示範資料）。
