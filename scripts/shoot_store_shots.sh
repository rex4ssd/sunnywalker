#!/bin/zsh
# SunnyWalker 上架截圖（搭配 DEBUG 的 StoreShots 模式，見 SunnyWalker/Services/StoreShots.swift）
#
#   scripts/shoot_store_shots.sh <UDID> <輸出資料夾> [裝置標籤]
#
# 🔴 只准用在專用的截圖模擬器（會灌示範資料、改群組設定）。建法：
#   xcrun simctl create "SW-Shots-iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max <runtime>
#   xcrun simctl create "SW-Shots-iPad"   com.apple.CoreSimulator.SimDeviceType.iPad-Air-13-inch-M4 <runtime>
# 產出檔名 `NN_<畫面>_<裝置標籤>_<en|zh>.png`——尾巴的 _en/_zh 給 asc_push.py --screenshots 認 locale。
set -e
UDID=$1; OUT=$2; TAG=${3:-device}
[ -z "$UDID" ] || [ -z "$OUT" ] && { echo "用法：$0 <UDID> <輸出資料夾> [裝置標籤]"; exit 1; }
cd "$(dirname "$0")/.."
BID=app.rexcode.sunnywalker
DD=/tmp/dd-sunnywalker-shots
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
for _ in $(seq 1 60); do xcrun simctl list devices | grep -q "$UDID.*Booted" && break; sleep 2; done
xcodegen generate >/dev/null
xcodebuild -project SunnyWalker.xcodeproj -scheme SunnyWalker -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DD" build >/dev/null
xcrun simctl terminate "$UDID" $BID 2>/dev/null || true
xcrun simctl install "$UDID" "$DD/Build/Products/Debug-iphonesimulator/SunnyWalker.app"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

shoot() {  # <序號_名稱> <lang code> <en|zh> <screen> <group>
  xcrun simctl terminate "$UDID" $BID 2>/dev/null || true
  xcrun simctl launch "$UDID" $BID -StoreShots 1 -appLanguageCode "$2" -StoreShotScreen "$4" -StoreShotGroup "$5" >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "$OUT/$1_${TAG}_$3.png" >/dev/null 2>&1
  echo "  ✓ $1_${TAG}_$3.png"
}

for L in "zh-Hant zh" "en en"; do
  CODE=${L% *}; LOC=${L#* }
  # 換語言要重灌示範資料（標籤與群組名是灌進去的字）：先把 app 移除重裝＝清空資料。
  xcrun simctl terminate "$UDID" $BID 2>/dev/null || true
  xcrun simctl uninstall "$UDID" $BID 2>/dev/null || true
  xcrun simctl install "$UDID" "$DD/Build/Products/Debug-iphonesimulator/SunnyWalker.app"
  echo "▸ $LOC"
  shoot 01_home      $CODE $LOC home     0
  shoot 02_countdown $CODE $LOC home     2
  shoot 03_chime     $CODE $LOC editor   2
  shoot 04_new       $CODE $LOC new      0
  shoot 05_groups    $CODE $LOC settings 0
done
echo "完成 → $OUT"
