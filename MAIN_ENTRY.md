# SunnyWalker — Main Entry

_A voice-interactive alarm clock for 7-year-olds. iOS 17+, Swift + SwiftUI,
Studio-Ghibli watercolor aesthetic. 100% offline, no ads, no tracking.
_

Last updated: **2026-06-01T05:10:00+08:00**

> **This is the resume manifest. After a crash / shutdown / vacation, read this file first.**

## ▶️  Resume point
- Current day: **19**
- Last entry: `[D] Day 18` — `DONE`
- Next up: `[A] coder` (Day 19) — **P4 start: PermissionManager + AlarmKit auth + BedSideManager**
- Recovery command: `sw next`
- ⚠️ Pending manual git commit (see below)

## 🔧  Manual steps required
```bash
cd ~/Documents/SunnyWalker
rm .git/index.lock
git add SunnyWalker.xcodeproj/project.pbxproj SunnyWalker/Info.plist \
  SunnyWalker/SunnyWalker.entitlements SunnyWalker/Services/AlarmKitService.swift \
  SunnyWalker/Views/Home/HomeView.swift orchestrator/current/ring.md MAIN_ENTRY.md
git commit -m "Day 13: P0 AlarmKit PoC — iOS 26 target, AlarmKitService, entitlements, DEBUG test button"
rm SunnyWalker/Theme/Sounds/_totoro_breath.wav
```
- 🔑 Submit AlarmKit entitlement request: Xcode → Signing & Capabilities → "+" → "Alarms" → Apply

## ⏰  Schedule, cooldown & approval
- ✅ No active cooldown (cooldown_hours = 4.0)
- ✅ Today runs full A→B→C→D (no stop_after configured)

## 💓  Heartbeat (crash detection)
- No active heartbeat — system is idle / not running

## 🔁  Recent ring entries (last 8)
- ✅ `[D]` Day  4  2026-05-31 16:28:00+08:00  End Day 4
- ✅ `[D]` Day  5  2026-05-31 22:42:00+08:00  End Day 5
- ✅ `[D]` Day  6  2026-05-31 23:47:00+08:00  End Day 6
- ✅ `[D]` Day  7  2026-06-01 00:35:00+08:00  End Day 7
- ✅ `[D]` Day  8  2026-06-01 02:08:00+08:00  End Day 8
- ✅ `[D]` Day  9  2026-06-01 03:15:00+08:00  End Day 9
- ✅ `[D]` Day 10  2026-06-01 11:15:00+08:00  End Day 10
- ✅ `[D]` Day 11  2026-06-01 11:45:00+08:00  End Day 11

Full ring: `orchestrator/current/ring.md`

## 📋  Recent daily reports (2-min reads)
- `orchestrator/reports/daily/2026-05-29.md`
- `orchestrator/reports/daily/2026-05-30.md`
- `orchestrator/reports/daily/2026-05-31.md`
- `orchestrator/reports/daily/2026-06-01.md`

## 📅  Weekly reports
- `orchestrator/reports/weekly/2026-W22.md`

## 📝  Live progress
- `orchestrator/progress/progress.md`

## 🗂️  Active verbose logs (not yet archived)
- `orchestrator/logs/2026-05-29`
- `orchestrator/logs/2026-05-30`
- `orchestrator/logs/supervisor`

