#!/bin/bash
#
# generate_mascot_voices.command
# 產生「小鬧晴」吉祥物點一下會講的可愛問候語音。
#
# 作法：用 macOS 內建 `say` 直接合成成 AIFF（音高用 say 內建 [[pbas]] 提高 → 可愛、不破音）。
# 不做任何轉檔（不碰 afconvert / ffmpeg），所以不會有取樣率不符或編碼器 '!dat' 的問題。
# AIFF 在 iOS / AVAudioPlayer 原生就能播。
#
# 終端機跑（看得到訊息）：
#     cd /Users/lion/Documents/SunnyWalker
#     bash Scripts/generate_mascot_voices.command
#
# 可調參數：
#     VOICE  聲音（預設 Samantha，沒裝自動換備援）   say -v '?' 可列出
#     RATE   語速 wpm（預設 168，越大越快）
#     PBAS   音高（預設 58；越大越高越可愛，約 40~68 之間試）
#   例： VOICE=Samantha RATE=165 PBAS=64 bash Scripts/generate_mascot_voices.command

set -uo pipefail
cd "$(dirname "$0")"

OUT_DIR="$(pwd)/mascot_voices"
RATE="${RATE:-168}"
PBAS="${PBAS:-58}"
WANT_VOICE="${VOICE:-Samantha}"

phrases=(
"Good morning! It's a beautiful day!"
"Rise and shine, sleepy head!"
"Wakey wakey! Time to play!"
"Hello sunshine! I missed you!"
"Yay! You're awake! Let's have fun today!"
"Good morning, superstar!"
"Time to get up and shine so bright!"
"Hi there! Ready for an awesome day?"
)

command -v say >/dev/null 2>&1 || { echo "❌ 找不到 say —— 要在 macOS 上跑。"; exit 1; }

voice_available() { say -v '?' | awk '{print $1}' | grep -qx "$1"; }
VOICE=""
if voice_available "$WANT_VOICE"; then
  VOICE="$WANT_VOICE"
else
  echo "⚠️  聲音「$WANT_VOICE」沒安裝，改試備援…"
  for v in Samantha Alex Daniel Karen Moira Tessa Allison Ava Fred; do
    if voice_available "$v"; then VOICE="$v"; break; fi
  done
fi
if [ -n "$VOICE" ]; then VOICE_ARG=(-v "$VOICE"); else VOICE_ARG=(); echo "⚠️  改用系統預設聲音。"; fi

mkdir -p "$OUT_DIR"
# 先清掉這個資料夾舊的壞檔（含先前 m4a），避免新舊混在一起
rm -f "$OUT_DIR"/mascot_greet_*.aiff "$OUT_DIR"/mascot_greet_*.m4a 2>/dev/null

echo "🎙  voice=${VOICE:-系統預設}  rate=$RATE  pbas(音高)=$PBAS"
echo "    輸出：$OUT_DIR"
echo ""

ok=0; fail=0; i=1
for p in "${phrases[@]}"; do
  n=$(printf "%02d" "$i")
  out="$OUT_DIR/mascot_greet_$n.aiff"

  # [[pbas N]] = say 內建提高音高；直接輸出 AIFF，不再轉檔
  if say "${VOICE_ARG[@]}" -r "$RATE" -o "$out" "[[pbas $PBAS]] $p" && [ -f "$out" ]; then
    echo "  ✓ mascot_greet_$n.aiff  ←  \"$p\""; ok=$((ok+1))
  else
    echo "  ✗ say 失敗：\"$p\""; fail=$((fail+1))
  fi
  i=$((i+1))
done

echo ""
echo "✅ 成功 $ok 個、失敗 $fail 個 → $OUT_DIR"
echo ""
echo "試聽： afplay $OUT_DIR/mascot_greet_01.aiff"
echo ""
echo "👉 接進 App（先刪掉舊的壞 m4a，再放新 aiff）："
echo "   rm -f SunnyWalker/Theme/Sounds/mascot_greet_*.m4a"
echo "   mv -f $OUT_DIR/mascot_greet_*.aiff SunnyWalker/Theme/Sounds/"
echo "   xcodegen generate          # 這次副檔名變了(m4a→aiff)，一定要跑"
echo "   然後 Xcode ⌘⇧K 清乾淨再 Run。"
