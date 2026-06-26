# SunnyWake — Swift + SwiftUI 完整規格書

> 給 7 歲兒童的「語音互動鬧鐘」。100% 離線、無廣告、無追蹤、宮崎駿手繪風。
> 本文件為 AI 開發助手（Claude / Cursor / Copilot）的系統提示與實作藍圖。
> 目標平台：iOS 17+（iPhone 主，iPad 相容）。

---

## 0. 為什麼是 Swift + SwiftUI（不是 Tauri）

| 關鍵點 | 結論 |
|---|---|
| 鬧鐘背景排程 | iOS 只允許 `UNUserNotificationCenter`，Swift 直接呼叫；Tauri 要寫 bridge |
| 離線語音辨識 | Swift 內建 `SFSpeechRecognizer` + `requiresOnDeviceRecognition = true`，免下載 vosk model |
| 兒童類別審查 | Apple 偏好 native，webview 殼常被退件 |
| App size | 10–20 MB（Tauri + vosk model 50 MB+） |
| 開發時程 | MVP 約 2–3 週，Tauri 至少 4–6 週還要對抗工具鏈 |

---

## 1. 環境準備

### 系統與工具鏈
- **macOS**: Sonoma 以上
- **Xcode**: 15.x（含 Command Line Tools、iOS 17 SDK）
- **Apple Developer Program**: 必須（US$99/年，上架前付）
- **實機**: 建議準備一台 iPhone 真機測試麥克風與通知行為

### 專案建立
```bash
# Xcode → File → New → Project → iOS → App
# Product Name: SunnyWake
# Interface: SwiftUI
# Language: Swift
# Storage: SwiftData（iOS 17+）
# Include Tests:
```

### Info.plist 必填鍵
```xml
<key>NSMicrophoneUsageDescription</key>
<string>鬧鐘需要聽你說「我起床了」才能關掉喔！聲音只留在這台 iPhone 裡，不會傳出去。</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>用來聽懂你說的話，把鬧鐘關掉。所有辨識都在這台裝置上完成。</string>

<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### Capabilities（Xcode → Signing & Capabilities）
- Push Notifications：**不要**勾（會被誤判收集資料）
- Background Modes → Audio：（鬧鐘響時前景播音）

---

## 2. 專案檔案結構

```
SunnyWake/
├── SunnyWakeApp.swift            # @main 進入點
├── ContentView.swift              # Root NavigationStack
│
├── Models/
│   ├── Alarm.swift                # @Model class，SwiftData
│   ├── VoiceClip.swift            # 家長錄音檔 metadata
│   └── WakePhrase.swift           # 喚醒關鍵字（"我起床了" / "好的"）
│
├── Views/
│   ├── Home/
│   │   ├── HomeView.swift         # 主畫面：時間 + 龍貓 + 鬧鐘列表
│   │   └── CloudBackground.swift  # 飄動的雲朵背景
│   ├── Alarm/
│   │   ├── AlarmListView.swift    # 卡片列表
│   │   ├── AlarmRingView.swift    # 鬧鐘響起的全螢幕
│   │   └── RewardView.swift       # 成功關閉後的彩帶獎勵
│   ├── Settings/
│   │   ├── ParentalGateView.swift # 家長閘門
│   │   ├── AlarmEditorView.swift  # 新增/編輯鬧鐘
│   │   └── RecordingView.swift    # 錄音介面
│   └── Components/
│       ├── GhibliButton.swift     # 主要按鈕元件
│       ├── WatercolorCard.swift   # 水彩卡片
│       └── TotoroAvatar.swift     # 龍貓吉祥物（會眨眼睛）
│
├── Services/
│   ├── AlarmScheduler.swift       # UNUserNotificationCenter 包裝
│   ├── AudioRecorder.swift        # AVAudioRecorder
│   ├── AudioPlayer.swift          # AVAudioPlayer
│   ├── SpeechRecognizer.swift     # SFSpeechRecognizer (on-device)
│   └── PermissionManager.swift    # 集中要權限
│
├── Theme/
│   ├── GhibliColors.swift         # 色票
│   ├── GhibliFonts.swift          # 字型
│   ├── Animations.swift           # 雲朵飄動 / 樹葉搖擺
│   └── Sounds/
│       ├── totoro_breath.caf      # UI 互動音效（≤30s, 系統格式）
│       └── leaf_rustle.caf
│
├── Assets.xcassets/
│   ├── AppIcon.appiconset         # 龍貓撐傘
│   ├── Totoro/                    # 角色立繪（多個表情）
│   ├── Backgrounds/               # 水彩天空、森林、星空
│   └── Icons/                     # 自訂手繪 icon
│
└── Resources/
    └── Recordings/                # 使用者錄音存放（FileManager 動態建立）
```

---

## 3. 宮崎駿視覺指南

### 3.1 色彩計畫（GhibliColors.swift）

```swift
import SwiftUI

enum GhibliColors {
    // 天空藍：龍貓躺在草地上看的天空
    static let skyBlue       = Color(red: 0.62, green: 0.82, blue: 0.91)  // #9ED1E8
    static let cloudWhite    = Color(red: 0.98, green: 0.97, blue: 0.93)  // #FAF8ED

    // 森林綠：龍貓的森林、風之谷
    static let forestDeep    = Color(red: 0.27, green: 0.43, blue: 0.34)  // #456E57
    static let leafFresh     = Color(red: 0.56, green: 0.74, blue: 0.45)  // #8FBC72

    // 麥田金：風起、神隱少女的燈籠
    static let wheatGold     = Color(red: 0.95, green: 0.78, blue: 0.36)  // #F3C75C
    static let lanternOrange = Color(red: 0.93, green: 0.55, blue: 0.31)  // #ED8C4F

    // 夜空：龍貓夜晚等公車、千與千尋的湯屋
    static let nightIndigo   = Color(red: 0.18, green: 0.21, blue: 0.42)  // #2E366B
    static let starGold      = Color(red: 0.99, green: 0.95, blue: 0.74)  // #FCF2BD

    // 龍貓灰
    static let totoroGray    = Color(red: 0.42, green: 0.42, blue: 0.45)  // #6B6B73
}
```

### 3.2 字型（GhibliFonts.swift）

- **主字型**：`jf open 粉圓` 或 `源樣黑體`（粉圓更適合兒童）
  - 內建免費商用，下載後加入 `Targets → Build Phases → Copy Bundle Resources`
- **fallback**：`Apple SD Gothic Neo`（系統內建圓潤字）
- **Size**：標題 32pt / 內文 22pt / 按鈕 24pt（兒童手指好按）

### 3.3 動畫元素（Animations.swift）

| 元素 | 行為 | API |
|---|---|---|
| 雲朵飄動 | 由左往右無限循環，3 朵不同速度 | `.offset(x:)` + `withAnimation(.linear.repeatForever)` |
| 龍貓眨眼 | 每 5 秒眨一次 | `Timer.publish` + state |
| 樹葉飄落 | 鬧鐘響時觸發 | `SpriteKit` 粒子（或純 SwiftUI 多個 Image） |
| 彩帶獎勵 | 成功喊「我起床了」後 | 開源套件 `ConfettiSwiftUI`（純 SwiftUI 實作） |
| 按鈕按壓 | scale(0.92) + haptic | `.sensoryFeedback(.impact)` |

### 3.4 場景與時間連動

```swift
// HomeView 背景根據時段切換
enum DaytimeScene {
    case dawn    // 5-7 點：粉橘日出，麥田
    case morning // 7-11 點：藍天白雲，森林
    case noon    // 11-15 點：亮藍天，向日葵田
    case dusk    // 15-19 點：橘紅夕陽，紅燈籠
    case night   // 19-5 點：深藍星空，龍貓打傘
}
```

> 不只是色票，每個場景**換背景圖+主角姿勢**，孩子打開 App 會有「世界在變」的驚喜感。

### 3.5 視覺資產來源建議

- **付費合理**：Adobe Stock / Shutterstock 搜「watercolor children illustration」
- **AI 生成**：Midjourney prompt：`"studio ghibli style, watercolor, soft pastels, totoro forest, cute child, hand-painted texture --ar 9:19"`，記得**人工再修**避免版權風險
- **務必避免**：直接抓吉卜力工作室作品，會被 Apple 駁回且觸犯著作權

---

## 4. 核心功能實作

### 階段一：家長閘門（ParentalGateView）

> Apple 規定：題目必須「孩子算不出來」，純兩位數加法 **不夠**。改用「找出順序對的星期」或三位數乘法。

```swift
struct ParentalGateView: View {
    @State private var answer = ""
    @State private var question = GateQuestion.random()
    let onSuccess: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("請大人幫忙").font(.title2)
            Text(question.prompt).font(.title).bold()
            // 範例：「請按順序：星期三、星期一、星期日」
            // 改成 picker 不要鍵盤，避免大數字題
            ForEach(question.options, id: \.self) { opt in
                GhibliButton(opt) { check(opt) }
            }
        }
        .padding()
        .background(GhibliColors.cloudWhite)
    }
}

struct GateQuestion {
    let prompt: String
    let options: [String]
    let correct: String

    static func random() -> GateQuestion {
        // 範例：將星期照順序排列、找出最大的兩位數、選出三角形
        // 重點：用「概念題」而非單純算術，更符合 Apple 兒童指南
        ...
    }
}
```

### 階段二：錄音（AudioRecorder.swift）

```swift
import AVFoundation

@MainActor
final class AudioRecorder: ObservableObject {
    private var recorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var currentURL: URL?

    func start(named name: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings/\(name).m4a")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        currentURL = url
        isRecording = true
    }

    func stop() {
        recorder?.stop()
        isRecording = false
    }
}
```

### 階段三：鬧鐘排程（AlarmScheduler.swift）

> **重要**：iOS 不允許 App 自己在背景跑 timer。必須走 `UNUserNotificationCenter` 註冊本地通知，系統會幫你叫醒孩子。

```swift
import UserNotifications

@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()

    func requestPermission() async throws {
        try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(alarm: Alarm) async throws {
        let content = UNMutableNotificationContent()
        content.title = "起床囉！"
        content.body = "點開來聽 \(alarm.recordingName)"

        // 自訂音檔（≤30s，必須放在 main bundle 或 Library/Sounds）
        content.sound = UNNotificationSound(
            named: UNNotificationSoundName(rawValue: alarm.soundFileName)
        )
        content.categoryIdentifier = "SUNNYWAKE_ALARM"
        content.userInfo = ["alarmID": alarm.id.uuidString]

        var date = DateComponents()
        date.hour = alarm.hour
        date.minute = alarm.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let req = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: trigger)

        try await UNUserNotificationCenter.current().add(req)
    }

    func cancel(_ alarmID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [alarmID.uuidString])
    }
}
```

**音檔限制**：notification sound 上限 30 秒、必須是 `.caf` / `.aiff` / `.wav`。家長錄製的 `.m4a` 要先轉檔（用 `AVAssetExportSession` 或 `afconvert` 預處理）。

### 階段四：離線語音辨識（SpeechRecognizer.swift）

```swift
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var recognizedText = ""
    @Published var matchedKeyword: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))!
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private let keywords = ["我起床了", "好的", "知道了", "起床囉"]

    func startListening(onMatch: @escaping (String) -> Void) throws {
        guard recognizer.supportsOnDeviceRecognition else {
            throw NSError(domain: "Speech", code: -1)
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.requiresOnDeviceRecognition = true  // 關鍵：100% 離線
        request?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request!) { [weak self] result, error in
            guard let self, let text = result?.bestTranscription.formattedString else { return }
            self.recognizedText = text

            if let hit = self.keywords.first(where: { text.contains($0) }) {
                self.matchedKeyword = hit
                onMatch(hit)
                self.stop()
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
    }
}
```

**防誤觸設計**：
- 關鍵字長一點（「我起床了」優於「好」）
- 要求至少 2 個字以上才觸發
- 鬧鐘響後**5 秒**才開始聽（避免播音檔自己觸發）

### 階段五：鬧鐘響起的全螢幕流程（AlarmRingView）

```
[通知響] → 孩子點 banner → App 進前景 → AlarmRingView
                                          ├─ 播放家長錄音 (AVAudioPlayer, loop)
                                          ├─ 5 秒後啟動 SpeechRecognizer
                                          ├─ 龍貓在搖動，雲朵飄
                                          └─ 偵測到「我起床了」
                                              ├─ 停止播放 + 停止辨識
                                              ├─ 切到 RewardView（彩帶+「你好棒！」）
                                              └─ 3 秒後回 HomeView
```

---

## 5. SwiftData 資料模型

```swift
import SwiftData

@Model
final class Alarm {
    @Attribute(.unique) var id: UUID
    var label: String
    var hour: Int
    var minute: Int
    var weekdays: [Int]       // 1=Sunday … 7=Saturday
    var isEnabled: Bool
    var recordingName: String // 對應 VoiceClip
    var createdAt: Date

    init(label: String, hour: Int, minute: Int, recordingName: String) {
        self.id = UUID()
        self.label = label
        self.hour = hour
        self.minute = minute
        self.weekdays = [2,3,4,5,6]  // 預設週一到週五
        self.isEnabled = true
        self.recordingName = recordingName
        self.createdAt = .now
    }
}

@Model
final class VoiceClip {
    @Attribute(.unique) var id: UUID
    var name: String         // "媽媽的早安"
    var fileName: String     // "morning_mom.caf"
    var duration: TimeInterval
    var createdAt: Date
}
```

---

## 6. App Store 上架合規清單

### 6.1 兒童類別必要設定（App Store Connect）
- App Information → Category: **Primary: Kids**
- Age Rating → Made for Kids: **Ages 6–8**
- Kids Age Band：選 6–8（你的 TA 是 7 歲）

### 6.2 隱私問卷（Privacy Nutrition Label）
全部選 **「Data Not Collected」**：
- 沒有收集姓名、Email、位置、識別碼
- 沒有第三方分析（Firebase / GA 都不裝）
- 沒有第三方廣告 SDK（AdMob / Unity Ads 都不裝）

### 6.3 Privacy Policy（必填 URL）
寫一頁簡單的 GitHub Pages 就夠，內容範例：
```
SunnyWake does not collect, store, or transmit any personal data.
All recordings and voice recognition happen on your device.
No internet connection is required to use this app.
No third-party SDKs, no analytics, no ads.
Contact: keep.going@m2k.com.tw
```

### 6.4 審查重點（容易被退件的地雷）
| 項目 | 規定 |
|---|---|
| Parental Gate | 必須有，且題目不能是「2+3」這種兒童能解的 |
| 外部連結 | App 內**不可有**任何連到網站、Email、社群的按鈕（除非在 parental gate 後面） |
| 行銷 / 升級提示 | 不可有 IAP 或「升級高級版」提示 |
| 第三方角色 | 不可使用龍貓、千尋等角色形象（會被告或被退）→ 自己畫「致敬風格」 |
| 角色名稱 | App 名 SunnyWake OK，但宣傳文案別寫「宮崎駿風」「Ghibli style」→ 寫「水彩手繪風」 |

---

## 7. 開發里程碑（建議 3 週 MVP）

### Week 1：學習 + 骨架
- Day 1–2：跑 Apple 官方 SwiftUI Tutorial（Landmarks）
- Day 3：建專案、設定 Info.plist、跑 ContentView
- Day 4–5：寫 `Alarm` model + `AlarmListView`（純 UI，無功能）
- Day 6–7：寫 `AlarmScheduler`，能成功收到一個 local notification

### Week 2：核心功能
- Day 8–9：`AudioRecorder` + `AudioPlayer`，能錄能播
- Day 10–11：`SpeechRecognizer`，console 印出辨識文字
- Day 12：串起 `AlarmRingView` 流程（聽到關鍵字→停止）
- Day 13–14：`ParentalGateView` + Settings flow

### Week 3：美化 + 上架
- Day 15–16：套 Ghibli 視覺（背景、字型、按鈕、龍貓 avatar）
- Day 17：加 `ConfettiSwiftUI` + 樹葉飄落動畫
- Day 18：iPad layout 適配（用 `@Environment(\.horizontalSizeClass)`）
- Day 19：實機測試（早上真的 set 7 點看會不會響）
- Day 20：上架素材（icon、screenshot、preview video）
- Day 21：送審（審查通常 24–48 小時，被退件就改）

---

## 8. 風險與備案

| 風險 | 機率 | 備案 |
|---|---|---|
| 自訂音檔超過 30s 通知截斷 | 高 | 進前景後改用 AVAudioPlayer 長播 |
| 孩子根本不會講「我起床了」 | 中 | 提供「按大按鈕」備案，3 次語音失敗自動切按鈕模式 |
| 兒童類審查被退 | 中 | 不掛兒童類，改一般 Lifestyle，但年齡分級照標 |
| 繁中 on-device 辨識準確度低 | 低 | iOS 16+ 已支援，實測台灣腔 OK；備用簡中模型 |
| 龍貓造型被質疑抄襲 | 低–中 | 找插畫師原創「圓肚森林精靈」，避開耳朵與肚紋特徵 |

---

## 9. 下一步

立即動作：
1. **在 Apple Developer 註冊**（$99/年），等 1–2 天 approve
2. **Xcode 開新專案**，把本檔案路徑加進 Cursor / Claude 的 context
3. **從 Week 1 Day 3 開始**：先讓 `AlarmListView` 顯示假資料 + 加一顆「新增鬧鐘」按鈕

要不要我接著產出：
- (A) **Week 1 第一支可跑的 Swift 程式碼**（`SunnyWakeApp.swift` + `HomeView.swift` + 假鬧鐘資料），讓你今天就能在 Xcode 開起來看？
- (B) **視覺 mockup**（用 SVG/HTML 畫出 HomeView、AlarmRingView、RewardView 三張畫面的長相）？
- (C) **角色設計提示詞**（給 Midjourney / Stable Diffusion 用，產出原創「森林精靈」避免侵權）？
