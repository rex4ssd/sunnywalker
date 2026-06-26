SunnyWake (SunnyWake: 兒童語音互動鬧鐘) - 保留了 Sunny 的溫暖，並用 Wake 直擊「喚醒」的核心功能。




本文件為 AI 開發助手（如 Cursor, GitHub Copilot）的系統提示與實作藍圖。目標是開發一款專為 7 歲兒童設計的「語音互動鬧鐘」，具備家長錄音、本地語音辨識關閉等功能。必須完全符合 Apple App Store 的「兒童類別」與 COPPA 隱私規範。

## 1. 環境準備 (Environment Setup)

AI 助手在開始編寫程式碼前，請協助使用者確認並初始化以下開發環境：

### 系統與工具鏈
* **OS**: macOS (必須，用於編譯 iOS/Mac App Store 應用程式)
* **IDE**: Xcode (確保包含最新的 Command Line Tools)
* **Rust**: 最新穩定版 (`rustup default stable`)
* **Node.js**: v18 或以上 (推薦使用 `pnpm` 作為包管理器)
* **框架**: Tauri v2 (`npm create tauri-app@latest`)

### 後端依賴 (Rust `Cargo.toml`)
需包含以下核心套件：

```

```text
Full spec file generated successfully.

```toml
[dependencies]
tauri = { version = "2.0", features = [] }
serde = { version = "1.0", features = ["derive"] }
tokio = { version = "1.0", features = ["full"] }
rodio = "0.17"      # 用於播放家長錄製的鬧鐘音訊
cpal = "0.15"       # 捕捉麥克風音訊輸入
vosk = "0.3"        # 本地端離線語音辨識 (關鍵！)
hound = "3.5"       # 處理 WAV 音訊格式

```

### 語音模型準備

* 下載輕量級繁體中文模型（例如 `vosk-model-small-cn`）。
* 將模型資料夾放置於 Tauri 的 `src-tauri/resources/model` 目錄下，並設定 `tauri.conf.json` 將其打包進 App 中。

---

## 2. 核心功能實作 (Core Features)

請依照以下順序分階段實作：

### 階段一：家長控制閘門 (Parental Gate) - **合規必要**

* **觸發時機**：進入「設定鬧鐘」或「錄製音訊」畫面之前。
* **邏輯**：隨機產生一道兩位數的加減法題目（例如：`25 + 14 = ?`）。
* **驗證**：只有輸入正確答案才能解鎖設定區域。

### 階段二：家長錄音功能 (Voice Recording)

* 呼叫 Rust 透過麥克風錄製一段簡短的音訊（例如：「寶貝該起床囉！」）。
* 將音訊儲存為 `.wav` 格式於裝置的本地應用程式資料夾 (App Data Directory) 中。

### 階段三：背景排程與音訊播放 (Alarm Scheduling & Playback)

* 使用 Rust `tokio::time` 或 cron-like 套件建立定時器。
* 時間到達時，使用 `rodio` 讀取並迴圈播放剛才錄製的 `.wav` 檔案。
* 觸發 Tauri Event 通知前端顯示「鬧鐘響起」的畫面。

### 階段四：本地端語音關閉 (Offline Speech Recognition)

* 鬧鐘響起同時，啟動 `cpal` 錄製麥克風串流。
* 將音訊串流送入 `vosk` 模型進行**即時且完全離線**的辨識。
* **關鍵字監聽**：設定目標詞彙（如："好的", "起床了", "知道"）。
* **觸發關閉**：當辨識到關鍵字，立即停止播放鬧鐘音訊，並關閉麥克風監聽，傳送事件給前端顯示獎勵畫面。

---

## 3. 視覺與 UI/UX 設計 (Visual Design for 7-year-olds)

前端 UI 實作請遵循以下兒童友善的設計原則：

### 色彩計畫 (Color Palette)

* **主色調**：高對比度且溫暖的柔和色彩（如：天空藍 `#87CEEB`、向日葵黃 `#FFD700`、蘋果綠 `#8FBC8F`）。
* **避免**：過於刺眼的螢光色或過於冷峻的深色模式（除非是睡眠模式的星空背景）。

### 排版與字型 (Typography & Layout)

* **字型**：使用圓潤、無襯線的字型（Rounded Sans-serif），字體要大（Base size: 18px-24px）。
* **按鈕**：巨大、帶有圓角 (`border-radius: 20px`) 與立體陰影 (`box-shadow`)，點擊時要有明顯的下壓動畫（`transform: scale(0.95)`）。

### 介面元素與回饋 (UI Elements & Feedback)

* **圖示為主**：減少文字閱讀負擔。設定用「齒輪」加「鎖頭」表示（暗示需要家長解鎖），錄音用「大麥克風」，鬧鐘響起用「太陽/月亮」。
* **視覺回饋**：當孩子說出「好的」成功關閉鬧鐘時，全螢幕噴發彩帶（Confetti 動畫），並顯示一個巨大的「你好棒！」圖案。

---

## 4. App Store 上架與隱私合規 (App Store Compliance)

AI 在配置專案時，必須確保符合 Apple 針對兒童類別的嚴格規定：

1. **無外部網路請求**：語音資料 **絕對不可** 送往 Google, AWS 或任何雲端 API。必須 100% 依賴 `vosk` 離線運作。
2. **Info.plist 隱私宣告**：
```xml
<key>NSMicrophoneUsageDescription</key>
<string>鬧鐘需要使用麥克風來聽你說「好的」以關閉鬧鐘。所有的聲音都只留在這台裝置上，絕對不會傳送出去喔！</string>

```


3. **無廣告、無追蹤**：App 內不可包含任何第三方廣告 SDK (如 AdMob) 或分析工具 (如 Google Analytics)。
"""

with open("kids_alarm_full_spec.md", "w", encoding="utf-8") as f:
f.write(markdown_content)

print("Full spec file generated successfully.")

```
這份包含「環境準備」、「核心功能」、「視覺設計」與「上架合規」的完整 `.md` 規格書已經為你準備好了：

[file-tag: code-generated-file-0-1780025930904451162]

你可以直接將這個檔案下載，並作為提示詞（Prompt）完整餵給你的 AI 開發助手（如 Cursor 或 GitHub Copilot）。這份規格書的語氣和結構是專門設計給 AI 讀的，能確保它在生成程式碼時，不會漏掉家長閘門或離線辨識這些上架的關鍵條件。

要讓 AI 開始動工，我們需要決定前端 UI 的技術棧。你比較偏好讓 AI 使用 **React (搭配 Tailwind CSS)** 來快速構建元件，還是使用 **Vue.js** 來開發這個鬧鐘的前端畫面呢？

```