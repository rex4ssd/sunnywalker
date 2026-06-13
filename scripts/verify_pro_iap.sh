#!/usr/bin/env bash
# verify_pro_iap.sh — SunnyWalker Pro (NT$50 終身 IAP) 驗收輔助
# branch: feature/pro-iap-lifetime
#
# 這支 script 只跑「機器能跑的」機械 gate（§5 / Review 第 1 層）：
#   1. 清 git lock（sandbox 殘留）  2. xcodegen generate  3. build  4. unit tests
#   5. xcstrings 雙語缺漏掃描        6. FeatureLimits 唯一上限來源檢查
# 真機 / StoreKit Transaction Manager 的人工項目印在最後當 checklist（只有你能做）。
#
# 用法：
#   cd ~/Documents/SunnyWalker && bash scripts/verify_pro_iap.sh
#   bash scripts/verify_pro_iap.sh --no-build   # 只做 generate + 靜態掃描，不 build/test

set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"   # repo root

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YEL=$'\033[0;33m'; BOLD=$'\033[1m'; NC=$'\033[0m'
ok()   { echo "${GREEN}✅ $*${NC}"; }
warn() { echo "${YEL}🟡 $*${NC}"; }
fail() { echo "${RED}🔴 $*${NC}"; }
hdr()  { echo; echo "${BOLD}=== $* ===${NC}"; }

DO_BUILD=1
[[ "${1:-}" == "--no-build" ]] && DO_BUILD=0
RC=0

# 0. stale git lock（sandbox 殘留，Mac 端可刪）------------------------------
hdr "0. git lock"
if [[ -f .git/index.lock || -f .git/HEAD.lock ]]; then
  rm -f .git/index.lock .git/HEAD.lock && ok "清掉殘留 lock" || { fail "lock 刪不掉"; RC=1; }
else
  ok "無殘留 lock"
fi

# 1. xcodegen generate（改了 project.yml 一定要跑，否則 90189 前科）---------
hdr "1. xcodegen generate"
if ! command -v xcodegen >/dev/null 2>&1; then
  fail "找不到 xcodegen → brew install xcodegen"; RC=1
else
  if xcodegen generate; then ok "xcodegen generate 完成"; else fail "xcodegen 失敗"; RC=1; fi
fi

# 2. xcstrings 雙語缺漏掃描（zh-Hant + en，Guideline 4 前科）-----------------
hdr "2. i18n — 每個 pro_ key 是否 zh-Hant + en 都有值"
python3 - <<'PY'
import json, sys
data = json.load(open("SunnyWalker/Localizable.xcstrings", encoding="utf-8"))
s = data["strings"]; missing = []
for k, v in s.items():
    if not k.startswith("pro_"):
        continue
    loc = v.get("localizations", {})
    for lang in ("en", "zh-Hant"):
        if not loc.get(lang, {}).get("stringUnit", {}).get("value"):
            missing.append((k, lang))
pro = sorted(k for k in s if k.startswith("pro_"))
print(f"pro_ keys: {len(pro)}")
if missing:
    print("🔴 缺漏:", missing); sys.exit(1)
print("✅ 16 keys 雙語齊全")
PY
[[ $? -ne 0 ]] && RC=1

# 3. FeatureLimits 唯一上限來源（view 不准散落第二份 hardcode）--------------
hdr "3. FeatureLimits 是唯一上限邊界"
LEAK=$(grep -rn "isPro ?" SunnyWalker --include=*.swift | grep -v "AppSettings.swift" | grep -v "StoreService.swift" || true)
if [[ -z "$LEAK" ]]; then ok "沒有 view 自己寫 isPro ? 三元上限"; else warn "發現可疑 isPro 三元（請人工確認）:"; echo "$LEAK"; fi

# 4. build + test ----------------------------------------------------------
if [[ $DO_BUILD -eq 1 ]]; then
  hdr "4. xcodebuild build + test（iOS Simulator）"
  DEST=$(xcrun simctl list devices available | grep -Eo 'iPhone [0-9].*\([0-9A-F-]{36}\)' | head -1 | grep -Eo '[0-9A-F-]{36}')
  if [[ -z "$DEST" ]]; then
    warn "找不到可用 iPhone 模擬器；用 generic destination"
    DESTARG=(-destination 'generic/platform=iOS Simulator')
  else
    ok "用模擬器 UDID $DEST"
    DESTARG=(-destination "platform=iOS Simulator,id=$DEST")
  fi
  echo "→ build-for-testing…"
  if xcodebuild build-for-testing -scheme SunnyWalker "${DESTARG[@]}" -quiet; then
    ok "build 過"
    echo "→ test（FeatureLimitsTests / GrandfatherSignalTests 等）…"
    if xcodebuild test-without-building -scheme SunnyWalker "${DESTARG[@]}" -quiet; then
      ok "tests 全綠"
    else fail "tests 有 fail"; RC=1; fi
  else fail "build 失敗"; RC=1; fi
else
  hdr "4. build/test — 略過（--no-build）"
fi

# 5. 人工 checklist（機器跑不了：StoreKit Transaction Manager + sandbox 真機）
hdr "5. 人工驗收 checklist（勾完才算過）"
cat <<'CHK'
A) Xcode → Run（scheme 已掛 Configuration.storekit；Debug → StoreKit Configuration 確認指到它）
   StoreKit local config（Debug → Xcode 選單 Debug ▸ StoreKit ▸ Manage Transactions）：
   [ ] 未購：第 7 顆鬧鐘被擋（既有 alert 文案不變）、第 6 則鈴聲被擋、單則鈴聲 5s cap、錄音 180s cap
   [ ] Settings 最下方出現 Pro row；displayPrice 顯示在地價（離線時「不顯示價格」而非 0/NT$50）
   [ ] 點 Pro row → ProUpgradeView → 解鎖鈕 → 系統 sheet → 成功 → 不重啟 App，四個上限即時全開
   [ ] 回 Settings：Pro 區變「已解鎖 ✓」靜態 row、沒有購買鈕
   [ ] Ask to Buy：Transaction Manager 設 Ask to Buy → 購買顯示「等待家長核准」→ Approve → 自動解鎖
   [ ] Refund：Transaction Manager ▸ Refund Purchase → isPro 回 false、超量資料保留只擋新增、不 crash
   [ ] 飛航模式啟動 App：已購狀態保持 Pro（currentEntitlements 走本地 cache）
   [ ] zh-Hant / en 切換：購買頁、pending、已解鎖三狀態字串都在位

B) Grandfather（既有用戶免費升級）— 用「先裝舊版再覆蓋」模擬：
   [ ] 先裝 main（1.1）建 1–2 顆鬧鐘 / 錄一段 → 再用本 branch build 覆蓋安裝（不刪 App）
       → 首次啟動 console 出現「🎁 Grandfather: pre-paid install detected」→ Settings 直接「已解鎖 ✓」
   [ ] 反向：模擬器 Erase 後乾淨裝本 branch → console「🆕 Grandfather: clean first install」→ 顯示購買鈕
   [ ] grandfathered 裝置「冷啟動兩次」：第二次仍是 Pro（refreshEntitlement 的 OR 沒把免費權利收回）

C) Sandbox 真機（local 過了再跑一輪）：
   [ ] ASC 建好 IAP（Ready to Submit）+ sandbox tester → 真機購買 / 回復購買 / 兒童帳號 Ask to Buy
   [ ] Family Sharing：家庭另一帳號裝置 → 回復購買 → 解鎖

D) 截圖（送審用）：
   [ ] ProUpgradeView 購買頁原樣（iPhone）→ ASC ▸ IAP ▸ Review Screenshot
   [ ] PNG 不可含 alpha（Lode 前科：App Store 任何 image slot 禁透明）
CHK

hdr "結論"
if [[ $RC -eq 0 ]]; then ok "機械 gate 全過 → 接著跑上面 A/B/C 人工項目"; else fail "機械 gate 有紅燈，先修再往下"; fi
exit $RC
