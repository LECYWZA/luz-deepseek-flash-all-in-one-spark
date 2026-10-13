#!/bin/bash
# v41_kfix_ab.sh — K gather 修复的**同靴单变量**端到端 A/B（2026-09-22 用户令）
#
# 为什么必须做：K 修复目前只有 (a) 单元级逐字节等价 14/14、(b) 算子级单次调用 A/B
# （fp4 取数 82.6→14.9 MiB/调用 @n=131072）。用户令「端到端 drain 降幅需要测量」——
# 要的是**整请求级 transient** 的降幅。跨靴对照（本靴 128K transient 3.5-3.7G）不是
# 隔离实验：只有同靴内先 old 后 new 各跑一次同一剂量才是单变量。
#
# 两臂（差**一个文件**）：
#   old = 镜像原版 deepseek_v4_memory_pool.py  md5 d9ec3730228a3feaecb9a480b462d5ef
#   new = 现役 overlay 版                      md5 f8f1fbe197d5872f563690461d7f98b3
# 其余四项 overlay 文件、env 内容（只换 SGLANG_OVERLAY_DIR 一行）、剂量（PRv3 131072-c1）、
# 量具（250ms 四机）全部同形。
#
# 纪律：不动现役 overlay/env（一律新建变体目录与变体 env）；不碰生产 8001（已停泊）；
#   不起保活单元；sudo 密码只经 stdin（绝不进 argv/日志）；每靴**断言**容器里挂的确实是
#   本臂那份 pool（形态=判据前提，缺了断言这实验就是自证）。
#
# 用法：bash v41_kfix_ab.sh            # 两臂都跑（约 30-40 分钟，建议后台）
#       ARM=old bash v41_kfix_ab.sh    # 只跑一臂（调试/重跑）
set -uo pipefail
export LC_ALL=C
umask 077   # 变体 env 是新写的文件，里面含 API_KEY ⇒ 一律 600 起（绝不因重定向掉到 644）
REPO="$HOME/dsv41-flash-dgxsparks"
cd "$REPO" || exit 9

LIVE_OVERLAY="$REPO/sglang-overlay.ctx600k"
OLD_OVERLAY="$REPO/sglang-overlay.ctx600k-oldpool"
LIVE_ENV=".env.tp4-600k"
OLD_ENV=".env.tp4-600k-oldpool"
CONTAINER="dsv41-head"
EP="http://127.0.0.1:8899"
OUTD="${OUTD:-$HOME/w6-logs/V41_KFIX_AB_$(date +%Y%m%d_%H%M)}"
mkdir -p "$OUTD"
LOG="$OUTD/AB.log"
say() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

KEY="$(grep -m1 '^API_KEY=' "$REPO/$LIVE_ENV" | cut -d= -f2- | tr -d '"'"'"'')"
PW="$(cat "$HOME/.sudopw" 2>/dev/null)"
[[ -n "$KEY" && -n "$PW" ]] || { say "⛔ 缺 API_KEY（$LIVE_ENV）或 ~/.sudopw"; exit 2; }

# ── 造 old 臂（幂等）───────────────────────────────────────────────────────────
mkdir -p "$OLD_OVERLAY"
for f in "$LIVE_OVERLAY"/*; do
  b="$(basename "$f")"
  [[ "$b" == deepseek_v4_memory_pool.py ]] && continue
  cp -f "$f" "$OLD_OVERLAY/$b"
done
docker cp "$CONTAINER:/tmp/old_pool.py" "$OLD_OVERLAY/deepseek_v4_memory_pool.py" 2>/dev/null \
  || cp -f /tmp/oldpool_check.py "$OLD_OVERLAY/deepseek_v4_memory_pool.py" 2>/dev/null || true
OLD_MD5="$(md5sum "$OLD_OVERLAY/deepseek_v4_memory_pool.py" 2>/dev/null | awk '{print $1}')"
NEW_MD5="$(md5sum "$LIVE_OVERLAY/deepseek_v4_memory_pool.py" 2>/dev/null | awk '{print $1}')"
[[ "$OLD_MD5" == d9ec3730228a3feaecb9a480b462d5ef ]] || { say "⛔ old 臂 pool 不是镜像原版（拿到 $OLD_MD5）⇒ 停手，别测出个假对照"; exit 2; }
[[ "$NEW_MD5" == f8f1fbe197d5872f563690461d7f98b3 ]] || { say "⛔ 现役 pool 变了（$NEW_MD5）⇒ 两臂定义需重核"; exit 2; }
# old 臂 env：只换 SGLANG_OVERLAY_DIR 一行（其余逐字节照抄现役 env）
sed "s|^SGLANG_OVERLAY_DIR=.*|SGLANG_OVERLAY_DIR=$OLD_OVERLAY|" "$REPO/$LIVE_ENV" >"$REPO/$OLD_ENV"
[[ "$(grep -c "^SGLANG_OVERLAY_DIR=$OLD_OVERLAY$" "$REPO/$OLD_ENV")" == 1 ]] || { say "⛔ old env 生成失败"; exit 2; }
say "两臂就绪：old=$OLD_MD5（$OLD_OVERLAY）；new=$NEW_MD5（$LIVE_OVERLAY）"
say "输出=$OUTD（两臂各自 OUTD 子目录 + LEDGER.tsv）"

drop_four() { # 四机 drop_caches（页缓存不 drop ⇒ KV 池缩水，两臂必须同条件）
  local h ip
  for h in dgxspark01 dgxspark02 dgxspark03 dgxspark04; do
    if [[ "$h" == "$(hostname)" ]]; then
      printf '%s\n' "$PW" | sudo -S sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null
    else
      ip="$(getent hosts "$h" | awk 'NR==1{print $1}')"
      ssh -n -o ConnectTimeout=8 -o "HostName=$ip" "$h" "sudo -S sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'" <<<"$PW" 2>/dev/null
    fi
    printf '   drop_caches: %s → 空闲 %s GiB\n' "$h" \
      "$(awk '/^MemFree:/{f=$2}/^Cached:/{c=$2}END{printf "%.1f",(f+c)/1048576}' /proc/meminfo 2>/dev/null)" >>"$LOG"
  done
}

wait_ready() { # 引擎就绪（最长 20 分钟）
  local i
  for i in $(seq 1 120); do
    if curl -fsS -m 8 -H "Authorization: Bearer $KEY" "$EP/v1/models" >/dev/null 2>&1; then return 0; fi
    sleep 10
  done
  return 1
}

assert_form() { # $1=期望 pool md5；断言容器里挂的就是本臂那份
  local want="$1" path got
  path="$(docker exec "$CONTAINER" sh -lc 'find /sgl-workspace -name deepseek_v4_memory_pool.py 2>/dev/null | head -1' 2>/dev/null)"
  got="$(docker exec "$CONTAINER" sh -lc "md5sum '$path' 2>/dev/null | cut -d' ' -f1" 2>/dev/null)"
  say "  形态断言：容器内 $path = ${got:-NA}（期望 $want）"
  [[ "$got" == "$want" ]]
}

run_arm() { # $1=old|new
  local arm="$1" envf exp ovs
  if [[ "$arm" == old ]]; then envf="$OLD_ENV"; exp="$OLD_MD5"; ovs="$OLD_OVERLAY"
  else envf="$LIVE_ENV"; exp="$NEW_MD5"; ovs="$LIVE_OVERLAY"; fi
  say "════ 臂 $arm 开始（env=$envf overlay=$ovs）"
  say "  ① 清栈"
  env ENV_FILE="$envf" bash start.sh stop >>"$OUTD/stop.$arm.log" 2>&1
  say "  ② 四机 drop_caches"
  drop_four
  say "  ③ 起栈 serve（预计 ~10 分钟）"
  if ! timeout 1800 env ENV_FILE="$envf" bash start.sh serve >>"$OUTD/serve.$arm.log" 2>&1; then
    say "  ⛔ serve 返回非 0 ⇒ 本臂失败（详见 serve.$arm.log 末尾）"
    tail -5 "$OUTD/serve.$arm.log" | sed 's/^/     /' | tee -a "$LOG" >&2
    return 1
  fi
  if ! wait_ready; then say "  ⛔ 引擎 20 分钟未就绪 ⇒ 本臂失败"; return 1; fi
  say "  ④ 形态断言（没有它，这实验只是自证）"
  assert_form "$exp" || { say "  ⛔ 形态断言失败 ⇒ 本臂作废"; return 1; }
  say "  ⑤ 剂量 131072-c1（PRv3，含 flush/基线/静置）"
  env ENV_FILE="$envf" OUTD="$OUTD/$arm" bash "$HOME/w6-kit/v41_dose_ladder.sh" 131072 >>"$OUTD/ladder.$arm.log" 2>&1
  say "  ⑥ 本臂剂量完成（ladder rc=$?）"
  grep -E '^[0-9]{4}' "$OUTD/$arm/LEDGER.tsv" 2>/dev/null | tail -1 | tee -a "$LOG" >&2
  return 0
}

for arm in ${ARM:-old new}; do
  run_arm "$arm" || say "臂 $arm 失败（继续下一臂，最后统一收栈）"
done

say "════ 收栈（留机器在停泊态）"
env ENV_FILE="$LIVE_ENV" bash start.sh stop >>"$OUTD/stop.final.log" 2>&1

# ── 汇总 ─────────────────────────────────────────────────────────────────────
{
  echo "K gather 同靴 A/B 汇总（$OUTD）"
  echo "两臂唯一差异：deepseek_v4_memory_pool.py"
  echo "  old = d9ec3730228a3feaecb9a480b462d5ef（镜像原版，无 K 修复）"
  echo "  new = f8f1fbe197d5872f563690461d7f98b3（3D 视图法）"
  echo
  printf '%-6s %-44s\n' 臂 "LEDGER 行（dose/phase/tps/wall/ttft/minid/minfree/dip/persist/trans/G1/G2/exit/note）"
  for arm in old new; do
    row="$(grep -E '^[0-9]{4}' "$OUTD/$arm/LEDGER.tsv" 2>/dev/null | tail -1)"
    printf '%-6s %s\n' "$arm" "${row:-<无行：本臂失败>}"
  done
  echo
  echo "判据：用户口径「瞬态峰值增量 ≤3G」= dip；transient=settled−min 是释放量（并列给出）"
  echo "形态断言（每臂起栈后容器内 pool md5）见 AB.log 的「形态断言」行。"
} >"$OUTD/SUMMARY.txt" 2>&1
cat "$OUTD/SUMMARY.txt" | tee -a "$LOG"
say "A/B 结束；汇总=$OUTD/SUMMARY.txt"
