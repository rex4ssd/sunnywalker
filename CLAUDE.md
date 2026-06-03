# SunnyWalker

> Python multi-agent orchestrator（claude loop / `orchestrator/`, `supervise.py`, `sw.py`）。
> 含一個 Swift iOS app 子專案（`SunnyWalker.xcodeproj`，XcodeGen `project.yml`）。

---

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
