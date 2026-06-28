# store_risk_check — SunnyWalker `[swift-app]`  (260628)

> 本檔由 `lode/scripts/store_risk_check.py` 自動產生，**給 AI coding agent（Claude Code / Codex）讀**。
> 請依 **P0 → P1 → P2** 順序修復；每項附【位置/影響】與【修法】。修完重跑該腳本驗證。
> 判讀準則：`lode/docs/STORE_RISK_SELFCHECK.md`。

**摘要：P0 0　P1 0　P2 2**

## P2 — 參考

- [ ] **寫死大字級(>34) ×9（多為裝飾性 emoji/大標，確認是否該固定）**  `GUI(4.1/破版)`
  - 位置/影響：SunnyWalker/Views/Settings/ParentalGateView.swift:78(size 48); SunnyWalker/Views/Settings/WakeHistoryView.swift:89(size 64); SunnyWalker/Views/Settings/VoiceLibraryView.swift:156(size 64); SunnyWalker/Views/Alarm/AlarmListView.swift:97(size 56); KidBrowser/KidBrowser/HomeView.swift:50(size 56); KidBrowser/KidBrowser/HomeView.swift:62(size 48); KidBrowser/KidBrowser/HomeView.swift:105(size 52); KidBrowser/KidBrowser/HomeView.swift:108(size 46)
  - 修法：大多是裝飾性圖像(emoji/遊戲圖)，固定尺寸通常是對的、不該隨 Dynamic Type 放大；若其實是大段標題文字才需改 @ScaledMetric。逐處人眼確認即可。
- [ ] **GUI 視覺相似（4.1 核心）無法靜態判定，仍須跑 app 截圖比對**  `GUI(4.1/破版)`
  - 修法：見 docs/GUI_RISK_SELFCHECK.md：截圖 + 與原生並排 + 大字/暗色 variant 壓測。
