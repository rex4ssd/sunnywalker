# SunnyWalker — Main Entry

_A voice-interactive alarm clock for 7-year-olds. iOS 26+, Swift + SwiftUI,
Studio-Ghibli watercolor aesthetic. 100% offline, no ads, no tracking.
_

Last updated: **2026-06-01T13:15:00+08:00**

> **This is the resume manifest. After a crash / shutdown / vacation, read this file first.**

## ▶️  Resume point
- Current day: **30**
- Last entry: `[A] Day 29` — `DONE`
- Status: **v1.0.0 feature complete** — P0–P6 delivered
- Next: TestFlight 上架 / 真機 AlarmKit 測試（需要 entitlement 批准）

## 🏁 Feature status (Day 29)
- ✅ P0 AlarmKit PoC scaffolding
- ✅ P1 StopAlarmIntent — lock-screen stop → AlarmRingView routing
- ✅ P2 AlarmTaskType voice/button — picker, migration-safe, test coverage
- ✅ P3 RewardView — spring bounce, wiggle, star burst, confetti
- ✅ P4 BedSideManager — dim screen, stay-on, force-quit brightness restore
- ✅ P5 WakeRecord + WakeHistoryView — parent history, response time
- ✅ P6 Edit/Delete alarms, PrivacyInfo.xcprivacy, Accessibility/reduceMotion

## 📊 Test count
- 60 pass + 1 skip (as of Day 28)
- Classes: Smoke, AlarmModel, VoiceClip, AudioPlayer, AlarmSound, WakePhrase,
  AudioRecorder, SpeechRecognizer, AppDelegateNotification, GateQuestion,
  VoiceFallback, AttemptCounter, CheckPendingAlarm, AlarmTaskType,
  EffectiveTaskType, WakeRecord, AlarmModelEdgeCase

## 🔧 Commit Day 24–29
```bash
cd ~/Documents/SunnyWalker
rm -f .git/HEAD.lock .git/index.lock
git add \
  SunnyWalker/Views/Settings/AlarmEditorView.swift \
  SunnyWalker/Views/Alarm/AlarmListView.swift \
  SunnyWalker/Views/Alarm/AlarmRingView.swift \
  SunnyWalker/Views/Alarm/RewardView.swift \
  SunnyWalker/Views/Components/TotoroAvatar.swift \
  SunnyWalker/Services/AlarmKitService.swift \
  SunnyWalker/PrivacyInfo.xcprivacy \
  SunnyWalker.xcodeproj/project.pbxproj \
  SunnyWalkerTests/SunnyWalkerTests.swift \
  orchestrator/current/ring.md MAIN_ENTRY.md
git commit -m "Day 24-29: edit/delete + privacy manifest + a11y + sound + v1.0.0

Day 24: AlarmEditorView edit mode; AlarmListView context menu / long-press editor
Day 25: Swipe-to-delete + context menu delete; AlarmKit cancel + UNUserNotificationCenter clear
Day 26: PrivacyInfo.xcprivacy — NSPrivacyTracking=false, UserDefaults+FileTimestamp APIs
Day 27: accessibilityReduceMotion in AlarmRingView+RewardView; TotoroAvatar VoiceOver labels
Day 28: AlertSound.named(.caf) in all AlarmConfiguration; AlarmModelEdgeCaseTests (5 tests)
Day 29: MARKETING_VERSION → 1.0.0; 60 pass + 1 skip"
git tag v1.0.0-rc1
git push origin dev/auto --tags
```

## ⚠️ 上架前必做
1. **AlarmKit entitlement** — 到 developer.apple.com 申請；沒有就無法真機測試
2. **真機測試** — 鎖屏響鈴、靜音突破、weekly repeat 正確性
3. **App icon** — `Assets.xcassets/AppIcon` 目前是 PIL "SW" placeholder；需要設計師出圖
4. **TestFlight** — 上傳 build，邀請內測
5. **App Store Connect** — 填寫 description、keywords、age rating（4+）、隱私政策 URL

## 📁 重要路徑
- Spec: `docs/design/DESIGN_v2.md`
- Dev plan: `docs/plan/DEV_PLAN_v2.md`
- Ring: `orchestrator/current/ring.md`
- Tests: `SunnyWalkerTests/SunnyWalkerTests.swift`
