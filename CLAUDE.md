# SunnyWalker

> Python multi-agent orchestrator（claude loop / `orchestrator/`, `supervise.py`, `sw.py`）。
> 含一個 Swift iOS app 子專案（`SunnyWalker.xcodeproj`，XcodeGen `project.yml`）。

---

## 變現政策（2026-07-18）

- 本 app 為兒童類，走**免費＋自由讚助（TipJarKit）**：三檔 Consumable 打賞，不解鎖任何功能。
- **Pro／付費牆／訂閱規劃一律暫停**；未經 Rex 明示不得新增任何付費功能。
- **已出貨的 SunnyWalker Pro（StoreService，含 grandfather）維持不動**；TipJar 是額外的自由讚助，兩者並存、互不相干。🔴 `StoreService.swift` 一行不准動。
- **TipJarSection 只能放家長閘（ParentalGate）後的家長頁**，絕不可出現在兒童流程；放置上與 Pro 購買 UI 保持距離避免混淆。

## App Store 文案鐵則（2026-07-25）
- **ASC metadata 一律不放 emoji／特殊圖示**：App 名稱、Subtitle、Promotional Text、Description、What's New、Keywords、Review Notes。Apple 不支援，屬退件風險。
- 判斷法：`docs/for_Apple_store/*`、`release_note/*` 裡 ```fence``` 內與行內反引號的內容＝要貼進 ASC 的值 → 不能有 emoji；fence 外的內部筆記與 ✅⬜🔴⚠️ 狀態標記不受限。
- **app 內部 UI 的 emoji 不受此限**（書架卡片圖示、TipJar 咖啡杯等照舊）。

## Vein — 學習 & 自我檢查（每次開工先做）

本專案的決策 / 踩雷 lore 存在 **Vein 中央 store**，tag = `project:sunnywalker`，外加跨專案的 `python` / `swift` / `multi-agent` / `coding-style`。
Cowork session 已掛 `vein-lore-plugin` MCP，直接呼叫工具，不用打 CLI。

🔴 **改 code 前 / 改完後一律自我檢查**（流程見 `vein/docs/self_check_playbook.md`）：

1. `vein_brief()` — 拿近期決策 + active pitfalls。
2. 撈相關的雷：
   - `vein_recall("<你要改的主題>")`
   - Python orchestrator 面：`vein_recall("python asyncio subprocess retry race")`
   - Swift app 面：`vein_recall("swift ios alarm background audio")`
   - 挑 `project:sunnywalker` + 對應 stack tag 的當 checklist。
3. 對著 `git diff` 逐條比對「有沒有重蹈這條雷」→ 標 🔴 違反 / 🟡 風險 / ✅ 對齊。
4. **發現沒記過的新雷 / 決策 → 馬上寫回：**
   `vein_log("pitfall", "症狀 + root cause + 修法", tags=["project:sunnywalker"])`
   `vein_log("decision", "為什麼選 X 不選 Y", tags=["project:sunnywalker"])`

> ⚠️ 目前本專案在 Vein 幾乎沒有專屬 lore——**邊開發邊用 `vein_log` 累積**，自檢才會越來越準。
> 之後若整理出 `docs/PITFALLS.md` 之類，可用通用 importer 批次匯入：
> ```bash
> cd /Users/lion/Documents/vein && python3 shell/import_project_lore.py \
>   --project sunnywalker --type pitfall --heading "##" --file ~/Documents/SunnyWalker/docs/<file>.md
> ```
