#!/usr/bin/env python3
# supervise.py
# ───────────────────────────────────────────────────────────────────────────────
# 長駐 supervisor：在你不在電腦前的時段，自動 loop 跑 `sw today`，
# 處理 cooldown / approval / weekday window，跑完一天 sleep 一段再開下一天。
#
# 用法：
#   python supervise.py
#       --max-days 7              跑滿 7 個 Day（即整個 7-day MVP）就退場
#       --idle-min 30             跑完一天後 sleep 30 分鐘再開下一天
#       --poll-min 5              cooldown / approval / window 擋住時 sleep 5 分鐘再試
#       --stop-after 06:00        到 06:00 就退場（怕你早上要用機器）
#       --max-failures 3          連續 N 次 cycle 失敗就停（避免燒 token）
#
# 建議搭配：
#   caffeinate -i nohup python supervise.py --stop-after 06:00 \
#       > /tmp/sw_supervise.log 2>&1 &
#   disown
#
# 退場條件（任一達到就乾淨結束）：
#   1. max_days 達成
#   2. stop_after 時間到
#   3. 連續 max_failures 次 cycle fail
#   4. Ring 進入 FAILED 狀態（D 寫 HUMAN ATTENTION 或無法 resolve）
#   5. Ctrl+C
# ───────────────────────────────────────────────────────────────────────────────

import argparse
import logging
import os
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from orchestrator.lib import notify, ring, schedule  # noqa: E402


# ── logger（同 schedule_entry.py 風格） ────────────────────────────────────────
LOG_DIR = ROOT / "orchestrator" / "logs" / "supervisor"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / f"supervise_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
LOCK_FILE = ROOT / "orchestrator" / "supervise.lock"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger("Supervise")


# ── Lock file 防呆：確保只有一個 supervise.py 在跑 ────────────────────────────
def _acquire_lock(force: bool = False) -> None:
    if LOCK_FILE.exists():
        try:
            old_pid = int(LOCK_FILE.read_text().strip())
            os.kill(old_pid, 0)  # 0 = 只檢查存活，不送 signal
            # 沒 raise → 那個 PID 還在跑
            if force:
                print(f"⚠️  --force: 終止舊 supervisor (PID {old_pid})...")
                os.kill(old_pid, signal.SIGTERM)
                time.sleep(2)
                try:
                    os.kill(old_pid, 0)   # 還活著就 SIGKILL
                    os.kill(old_pid, signal.SIGKILL)
                    print(f"   SIGKILL sent.")
                except ProcessLookupError:
                    pass
                print(f"   舊 process 已終止，繼續啟動。")
            else:
                print(f"❌  supervise.py 已在執行 (PID {old_pid})，拒絕重複啟動。")
                print(f"   停止舊的：kill {old_pid}")
                print(f"   強制重啟：加 --force 參數")
                sys.exit(1)
        except (ProcessLookupError, ValueError):
            # Stale lock（crash / 斷電殘留）→ 覆寫繼續
            print(f"⚠️  發現殘留 lock file（PID 已不存在），清除後繼續。")
    LOCK_FILE.write_text(str(os.getpid()))


def _release_lock() -> None:
    try:
        LOCK_FILE.unlink(missing_ok=True)
    except Exception:
        pass


# ── 子程序管理（Ctrl+C 時要乾淨關掉 sw today subprocess） ─────────────────────
_current_proc: subprocess.Popen | None = None
_model_override: str | None = None   # set by main() from --model


def _kill_current_proc():
    global _current_proc
    if _current_proc and _current_proc.poll() is None:
        logger.warning(f"🔫 終止子程序 PID {_current_proc.pid}")
        try:
            _current_proc.terminate()
            _current_proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            _current_proc.kill()
        except Exception as e:
            logger.warning(f"   terminate 失敗: {e}")


# ── 主執行：跑一次 sw today，stdout 直透 terminal（保留 ⟳ 進度效果） ───────────
def run_sw_today() -> int:
    global _current_proc
    cmd = [sys.executable, str(ROOT / "sw.py")]
    if _model_override:
        cmd += ["--model", _model_override]
    cmd += ["today"]
    logger.info(f"▶  spawning: {' '.join(cmd)}")
    t0 = time.time()
    # 不 capture stdout — 直接透傳到 terminal，⟳ / ✅ / ❌ 效果完整顯示
    _current_proc = subprocess.Popen(cmd, cwd=ROOT)
    rc = _current_proc.wait()
    dt_s = int(time.time() - t0)
    logger.info(f"◀  sw.py today exit rc={rc}  (took {dt_s}s)")
    _current_proc = None
    return rc


# ── 主迴圈 ───────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="SunnyWalker long-running supervisor")
    parser.add_argument("--max-days", type=int, default=7,
                       help="跑滿 N 個 Day 就退場（default 7）")
    parser.add_argument("--idle-min", type=int, default=30,
                       help="跑完一天 sleep 多少分鐘（default 30）")
    parser.add_argument("--poll-min", type=int, default=5,
                       help="被 gate 擋住時 sleep 多少分鐘（default 5）")
    parser.add_argument("--stop-after", default=None,
                       help="HH:MM 時間到就退場（例：06:00）")
    parser.add_argument("--max-failures", type=int, default=3,
                       help="連續失敗 N 次就停（default 3）")
    parser.add_argument("--model", default=None,
                       help="統一覆蓋所有 agent 模型（例：claude-sonnet-4-6）。"
                            "不指定就吃 config.yaml")
    parser.add_argument("--force", action="store_true",
                       help="若已有 supervisor 在跑，先 kill 再重啟")
    args = parser.parse_args()

    global _model_override
    _model_override = args.model

    _acquire_lock(force=args.force)   # 防呆：重複執行立即退場（--force 則先 kill 舊的）

    logger.info("=" * 70)
    logger.info(f"🤖 Supervisor 啟動 (PID {os.getpid()})")
    logger.info(f"   max_days={args.max_days}  idle_min={args.idle_min}  "
               f"poll_min={args.poll_min}  max_failures={args.max_failures}")
    if args.stop_after:
        logger.info(f"   stop_after={args.stop_after}")
    if args.model:
        logger.info(f"   model override → {args.model} (all agents)")
    else:
        logger.info(f"   model: per-agent from config.yaml")
    logger.info(f"   log: {LOG_FILE}")
    logger.info("=" * 70)

    # 記錄起始 day，用來算「我跑了幾個 day」
    start_day = ring.current_day()
    completed_days = 0
    consecutive_failures = 0

    # 啟動時若 stop_after 已經過了，這個 session 忽略它（避免立刻退場）
    _stop_after_ignored = False
    if args.stop_after:
        try:
            hh, mm = map(int, args.stop_after.split(":"))
            now = datetime.now()
            already_past = (now.hour, now.minute) >= (hh, mm) and (hh >= 12 or now.hour < 12)
            if already_past:
                logger.warning(
                    f"⚠️  stop_after={args.stop_after} 已過（現在 {now.strftime('%H:%M')}），"
                    f"本次 session 忽略，跑到 max_days 為止。"
                )
                _stop_after_ignored = True
        except ValueError:
            pass

    # Ctrl+C 善後
    def _sigint(signum, frame):
        logger.warning("\n⚠️  收到 Ctrl+C，準備乾淨退場...")
        _kill_current_proc()
        _release_lock()
        logger.info(f"🏁 Supervisor 結束。完成 {completed_days} 天。log: {LOG_FILE}")
        sys.exit(0)
    signal.signal(signal.SIGINT, _sigint)
    signal.signal(signal.SIGTERM, _sigint)
    signal.signal(signal.SIGHUP, _sigint)   # terminal 關閉時也乾淨退場

    while True:
        # ── 退場條件 1：max_days ──
        if completed_days >= args.max_days:
            logger.info(f"🎯 已完成 {completed_days}/{args.max_days} 天，退場。")
            break

        # ── 退場條件 2：stop_after 時間到 ──
        if args.stop_after and not _stop_after_ignored:
            try:
                hh, mm = map(int, args.stop_after.split(":"))
                now = datetime.now()
                if (now.hour, now.minute) >= (hh, mm):
                    # AM 時間（如 06:00）加早晨守衛，避免午夜跨日後立刻觸發
                    # PM 時間（如 23:00 / 18:00）直接判
                    if hh >= 12 or now.hour < 12:
                        logger.info(f"⏰ 到達 stop_after={args.stop_after}，退場。")
                        break
            except ValueError:
                logger.warning(f"⚠️  stop_after 格式錯誤 '{args.stop_after}'，忽略")

        # ── 退場條件 3：連續失敗 ──
        if consecutive_failures >= args.max_failures:
            logger.error(f"🚨 連續失敗 {consecutive_failures} 次，退場避免燒 token。")
            notify.notify_human_attention(
                day=ring.current_day(),
                reason=f"Supervisor 連續 {consecutive_failures} 次失敗，已停止。"
            )
            break

        # ── 退場條件 4：Ring 進入 FAILED ──
        # 還有重試次數 → auto-resolve 繼續跑；超過上限才退場
        try:
            ring.next_agent()
        except RuntimeError as e:
            if consecutive_failures < args.max_failures:
                consecutive_failures += 1
                logger.warning(
                    f"🔄 Ring FAILED，自動重試 "
                    f"({consecutive_failures}/{args.max_failures}): {e}"
                )
                try:
                    ring.mark_resolved()
                    logger.info("   ✅ Auto-resolved，重跑同一 agent。")
                except Exception as re2:
                    logger.error(f"   ❌ Auto-resolve 失敗: {re2}，退場。")
                    notify.notify_human_attention(
                        day=ring.current_day(),
                        reason=f"Auto-resolve 失敗: {str(re2)[:100]}"
                    )
                    _release_lock()
                    sys.exit(1)
                logger.info(f"😴 Sleep {args.poll_min} 分鐘後重試...")
                time.sleep(args.poll_min * 60)
                continue
            else:
                logger.error(
                    f"🚨 Ring FAILED 且已達重試上限 ({args.max_failures})。"
                    f"需要人類介入。"
                )
                notify.notify_human_attention(
                    day=ring.current_day(),
                    reason=f"Ring FAILED {args.max_failures} 次: {str(e)[:100]}"
                )
                break

        # ── Gate 檢查：cooldown / approval / window ──
        ok, reason, until = schedule.can_run_now()
        if not ok:
            wait_min = args.poll_min
            if until:
                # 已知何時可以再試 → sleep 到那個時間（最多 30 分鐘一輪）
                remaining = int((until - datetime.now().astimezone()).total_seconds() / 60)
                wait_min = min(max(remaining, 1), 30)
            logger.info(f"⏸  Blocked: {reason}.  Sleep {wait_min} 分鐘後再試。")
            time.sleep(wait_min * 60)
            continue

        # ── 真的跑 sw today ──
        before_day = ring.current_day()
        logger.info(f"🚀 Cycle 開始 — current_day={before_day}, "
                   f"completed={completed_days}/{args.max_days}")
        rc = run_sw_today()

        # ── Cycle 後的狀態判讀 ──
        last = ring.last()
        if last and last.agent == "D" and last.end_of_day is not None \
                and last.end_of_day >= before_day:
            # 成功收掉一天
            completed_days += 1
            consecutive_failures = 0
            logger.info(f"✅ Day {last.end_of_day} 完成。"
                       f"({completed_days}/{args.max_days})")
            if completed_days < args.max_days:
                logger.info(f"😴 Sleep {args.idle_min} 分鐘再開下一天...")
                time.sleep(args.idle_min * 60)
        else:
            # 沒完成（被 cooldown / approval / FAILED 等中斷）
            consecutive_failures += 1
            logger.warning(f"⚠️  Cycle 未完成一天 (rc={rc}). "
                          f"連續失敗 {consecutive_failures}/{args.max_failures}")
            logger.info(f"😴 Sleep {args.poll_min} 分鐘後再試...")
            time.sleep(args.poll_min * 60)

    _release_lock()
    logger.info(f"🏁 Supervisor 結束。完成 {completed_days} 天。log: {LOG_FILE}")


if __name__ == "__main__":
    main()
