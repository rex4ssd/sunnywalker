#!/usr/bin/env python3
"""
gen_audio.py — SunnyWalker 語音叮嚀產生器
使用 gTTS 產生英文 / 中文 / 中英雙語音檔

輸出：SunnyWalker/audio/<lang>/<id>.mp3

執行：
    python scripts/gen_audio.py
    python scripts/gen_audio.py --lang en       # 只產英文
    python scripts/gen_audio.py --lang zh       # 只產中文
    python scripts/gen_audio.py --lang bi       # 只產雙語
    python scripts/gen_audio.py --list          # 列出所有訊息不產檔
"""

import argparse
import os
import sys
from pathlib import Path

try:
    from gtts import gTTS
except ImportError:
    print("❌ gtts 未安裝：pip install gtts")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
AUDIO_DIR = ROOT / "audio"

# ── 訊息定義 ─────────────────────────────────────────────────────────────────
# 格式：id: { "en": "...", "zh": "...", "desc": "說明" }
MESSAGES = [
    {
        "id": "wake_up",
        "desc": "起床鬧鐘",
        "en": "Good morning, sunshine! Time to wake up! The day is waiting for you!",
        "zh": "早安！起床時間到了！今天是美好的一天，加油！",
    },
    {
        "id": "school",
        "desc": "上學時間",
        "en": "Time for school! Don't forget your backpack and water bottle. Have a great day!",
        "zh": "上學時間到了！記得帶書包和水壺，加油喔！",
    },
    {
        "id": "snooze_ok",
        "desc": "貪睡回應",
        "en": "Okay, five more minutes. But then it is really, really time to get up!",
        "zh": "好，再睡五分鐘。但五分鐘到就要真的起床喔！",
    },
    {
        "id": "nap",
        "desc": "午睡",
        "en": "Nap time! Close your eyes, take a deep breath, and rest. Sweet dreams!",
        "zh": "午睡時間！閉上眼睛，好好休息，做個好夢！",
    },
    {
        "id": "nap_end",
        "desc": "午睡結束",
        "en": "Rise and shine, little one! Nap time is over. Time to play!",
        "zh": "午睡時間結束了，起來活動一下吧！",
    },
    {
        "id": "meal",
        "desc": "吃飯",
        "en": "Mealtime! Come and eat while the food is still warm. Yummy!",
        "zh": "吃飯時間！趁食物還熱快來吃，很好吃喔！",
    },
    {
        "id": "bath",
        "desc": "洗澡",
        "en": "Bath time! Let's get all clean and sparkly. Splash splash!",
        "zh": "洗澡時間！來把身體洗得香香的吧！",
    },
    {
        "id": "teeth",
        "desc": "刷牙",
        "en": "Time to brush your teeth! Two whole minutes, okay? Up down, up down!",
        "zh": "刷牙時間！記得刷上刷下，刷滿兩分鐘喔！",
    },
    {
        "id": "bedtime",
        "desc": "睡覺",
        "en": "Bedtime! You did amazing today. Close your eyes and sleep tight. Good night!",
        "zh": "睡覺時間！今天表現很棒！閉上眼睛好好睡，晚安！",
    },
    {
        "id": "homework",
        "desc": "寫作業",
        "en": "Homework time! Let's get it done so we can play later. You've got this!",
        "zh": "寫作業時間！先把作業完成，之後就可以盡情玩了！",
    },
    {
        "id": "reading",
        "desc": "閱讀",
        "en": "Reading time! Pick your favorite book and let's go on an adventure!",
        "zh": "閱讀時間！拿起你最喜歡的書，開始冒險吧！",
    },
    {
        "id": "medicine",
        "desc": "吃藥提醒",
        "en": "Medicine time! Don't forget to take your medicine. It helps you stay healthy!",
        "zh": "吃藥時間！記得吃藥，這樣才會快快好起來！",
    },
    {
        "id": "drink_water",
        "desc": "喝水",
        "en": "Drink some water! Staying hydrated keeps you strong and happy!",
        "zh": "喝水時間！多喝水讓你精神好又健康！",
    },
    {
        "id": "exercise",
        "desc": "運動",
        "en": "Exercise time! Let's move our body. Jump, stretch, and have fun!",
        "zh": "運動時間！動動身體，跳一跳、伸伸懶腰，超有趣！",
    },
]


def make_bilingual(msg: dict) -> str:
    """中文先說，英文跟著說（中英雙語）"""
    return f"{msg['zh']}  {msg['en']}"


def gen_file(text: str, lang_code: str, out_path: Path) -> None:
    tts = gTTS(text=text, lang=lang_code, slow=False)
    tts.save(str(out_path))


def main() -> None:
    parser = argparse.ArgumentParser(description="SunnyWalker 語音叮嚀產生器")
    parser.add_argument(
        "--lang",
        choices=["en", "zh", "bi", "all"],
        default="all",
        help="產生語言：en=英文, zh=中文, bi=雙語, all=全部（預設）",
    )
    parser.add_argument("--list", action="store_true", help="只列出訊息，不產檔")
    parser.add_argument("--slow", action="store_true", help="慢速語音（對小孩更清晰）")
    args = parser.parse_args()

    if args.list:
        print(f"{'ID':<15} {'說明':<10} {'英文（前40字）'}")
        print("-" * 70)
        for m in MESSAGES:
            print(f"{m['id']:<15} {m['desc']:<10} {m['en'][:50]}")
        return

    langs_to_gen = (
        ["en", "zh", "bi"] if args.lang == "all" else [args.lang]
    )

    total = 0
    errors = 0

    for lang in langs_to_gen:
        out_dir = AUDIO_DIR / lang
        out_dir.mkdir(parents=True, exist_ok=True)

        lang_label = {"en": "英文", "zh": "中文", "bi": "雙語"}[lang]
        print(f"\n── {lang_label} ({lang}) ──────────────────────────")

        for msg in MESSAGES:
            out_path = out_dir / f"{msg['id']}.mp3"

            if lang == "en":
                text, tts_lang = msg["en"], "en"
            elif lang == "zh":
                text, tts_lang = msg["zh"], "zh-tw"
            else:  # bi
                text, tts_lang = make_bilingual(msg), "zh-tw"

            try:
                gen_file(text, tts_lang, out_path)
                size_kb = out_path.stat().st_size // 1024
                print(f"  ✅ {msg['id']:<18} {msg['desc']:<10} ({size_kb} KB)")
                total += 1
            except Exception as e:
                print(f"  ❌ {msg['id']:<18} {msg['desc']:<10} → {e}")
                errors += 1

    print(f"\n{'='*50}")
    print(f"完成：{total} 個音檔，{errors} 個錯誤")
    print(f"輸出目錄：{AUDIO_DIR}")
    if errors == 0:
        print("全部成功！可以把 audio/ 資料夾加進 Xcode 專案了。")


if __name__ == "__main__":
    main()
