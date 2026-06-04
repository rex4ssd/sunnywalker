# 小小瀏覽器 KidBrowser

給小孩用的「只能看指定網頁」iPhone / iPad app。
小孩在首頁點一張可愛卡片 → 全螢幕開該網址 → 點「回家」回到首頁。
**只有 `sites.json` 裡列出的確切網址能開**，點到頁面內任何外連都會被擋住跳不出去。

風格：柔和米色漸層、大圓角卡片、圓體大字、emoji 圖示。

---

## 一、結構

```
KidBrowser/
├── project.yml              # XcodeGen 設定（產生 .xcodeproj）
└── KidBrowser/
    ├── KidBrowserApp.swift  # App 進入點
    ├── HomeView.swift       # 可愛首頁 + 全螢幕網頁 + 回家鈕
    ├── WebView.swift        # WKWebView 嚴格白名單（核心）
    ├── SiteStore.swift      # 讀 sites.json、白名單比對、顏色工具
    ├── sites.json           # 👈 家長編輯這個：button 名稱 + 網址
    └── Info.plist
```

## 二、第一次 build（在你的 Mac 上）

需要 Xcode 與 XcodeGen（`brew install xcodegen`）。

```bash
cd ~/Documents/SunnyWalker/KidBrowser
xcodegen generate          # 產生 KidBrowser.xcodeproj
open KidBrowser.xcodeproj   # 用 Xcode 開
```

在 Xcode 裡：
1. 選一台實機（iPhone/iPad）或模擬器。
2. 若用實機，到 target → Signing & Capabilities，把 Team 換成你自己的 Apple ID（`project.yml` 裡預填的是 SunnyWalker 用的 team id，請換掉）。
3. 按 ▶︎ build & run。

> 免費 Apple ID 簽的 app 7 天會過期，需要重接電腦重簽一次；付費開發者帳號（US$99/年）就不會過期。

## 三、改網址（家長日常操作）

兩種方式，擇一：

**A. 直接改原始檔再 rebuild** — 編輯 `KidBrowser/sites.json`，重跑 `xcodegen generate` 與 build。

**B. 裝好後用 iPhone/iPad 的「檔案 app」改**（不用電腦）——
app 已開啟檔案分享，路徑：`檔案 app → 在我的 iPhone/iPad → 小小瀏覽器 → sites.json`。
改完存檔，回到 app 重開即可生效。

`sites.json` 格式：

```json
{
  "sites": [
    { "name": "世界城市", "url": "https://你的網站/kid/l2-1", "icon": "🌍", "color": "#FFD8A8" }
  ]
}
```

| 欄位    | 必填 | 說明 |
|--------|:--:|------|
| name   | ✅ | 卡片上的文字 |
| url    | ✅ | 點下去要開的**確切**網址（白名單就是比對這個） |
| icon   | ⬜️ | emoji（如 `🐞`）或 SF Symbol 名稱（如 `book.fill`）；省略則用 ⭐️ |
| color  | ⬜️ | 卡片顏色 hex，如 `#B2F2BB`；省略則用米色 |

> ⚠️ 嚴格白名單採「確切網址」比對（已忽略大小寫、結尾斜線、`#fragment`）。
> 例如只放 `https://站/kid/l2-1`，那麼 `https://站/kid/l2-2` 不會被允許——每一頁都要各自列一筆。
> 頁面裡嵌入的圖片 / 影片 / YouTube iframe 不受影響，照常顯示。

## 四、真正鎖死（不讓小孩切出 app）—— 用 iOS 內建「引導使用模式」

這部分不需寫程式，靠系統功能即可把畫面鎖在 app 裡：

1. 設定 → 輔助使用 → 引導使用模式 → 開啟，並設一組密碼。
2. 打開「小小瀏覽器」→ 連按三下側邊鍵（或 Home 鍵）→ 開始。
3. 結束時再連按三下、輸入密碼即可解開。

鎖定後小孩無法回主畫面、無法切換 app、無法關掉。

---

## 設計重點（給開發者）

- **白名單在 `WebView.swift` 的 `decidePolicyFor`**：主框架導航只放行 `sites.json` 的確切網址，其餘 `.cancel`；子框架/子資源（iframe、影片、圖片）放行，否則嵌入影片會載不出來。
- 影片設定：`allowsInlineMediaPlayback = true`、`mediaTypesRequiringUserActionForPlayback = []`。
- 關掉 `allowsBackForwardNavigationGestures`，避免小孩滑動亂跳。
- deploymentTarget 設 iOS 16，涵蓋大多數現役 iPhone/iPad。
- universal app（`TARGETED_DEVICE_FAMILY = "1,2"`），首頁用 `adaptive` GridItem 自動適應 iPhone 2 欄 / iPad 多欄。
