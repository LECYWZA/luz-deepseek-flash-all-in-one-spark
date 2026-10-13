#!/usr/bin/env bash
# overlay-drift-check.sh -- 在役容器读到的字节，是不是我们以为的那一份？
#
# 两种运行形态（start.sh 的 SGLANG_CODE_MOUNTS），**判据与处置完全不同**：
#   bind 模式（=1，开发）：overlay 逐文件 bind-mount。bind 钉住 inode，编辑器原地写
#     （vim / sed -i / 多数 IDE）会让容器继续读旧字节 —— 处置 = **重建容器**。
#   image 模式（=0，生产）：代码来自**镜像**。盘上改了而不重建镜像 ⇒ 容器永远看不到；
#     处置 = **重建镜像并分发**，此时重建容器一点用都没有（这条曾经是错的建议）。
#
# ★模式判定用**容器实际挂载**（docker inspect .Mounts），不看配置：配置可能和容器不一致，
#   而这里要回答的是"这个容器此刻到底读的是谁"。同一份 ground truth 也给出它来自哪个镜像
#   （.Config.Image），所以比对无需外部参数。
#
# 历史：本项目的每一次"我明明修了，怎么还这样"都是这个形状 —— fp4 KV scale 修复、
# bridge-id 保留修复，都只在盘上，直到容器重建才生效。别的工具看不见这一层：
# `--check/--apply` 挂进一次性容器，守卫看的是进程和内存，不是文件身份。
#
# 只读，可在服务中运行。
#
# Usage:
#   overlay-drift-check.sh                       # 自动挑 dsv41-head / dsv41-worker
#   overlay-drift-check.sh --container dsv41-head
#   overlay-drift-check.sh --quiet               # 只打结论
# Exit: 0=一致，1=有漂移（附带**该模式对应**的处置），2=用法/找不到
set -uo pipefail

REPO="${DSV41_REPO:-$HOME/dsv41-flash-dgxsparks}"
CONTAINER=""; QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --container) CONTAINER="${2:?}"; shift 2 ;;
    --repo)      REPO="${2:?}"; shift 2 ;;
    --quiet)     QUIET=1; shift ;;
    -h|--help)   sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -f "$REPO/start.sh" ] || { echo "FAIL: no $REPO/start.sh (pass --repo)" >&2; exit 2; }
if [ -z "$CONTAINER" ]; then
  for c in dsv41-head dsv41-worker; do
    docker inspect "$c" >/dev/null 2>&1 && { CONTAINER="$c"; break; }
  done
fi
[ -n "$CONTAINER" ] || { echo "FAIL: no dsv41-head/dsv41-worker container here (pass --container)" >&2; exit 2; }

# 与 start.sh / 镜像构建同一个单一事实源：overlay 映射。在这里重解析（而不是再抄一份）正是
# 这份检查保持诚实的原因。
mapfile -t PAIRS < <(python3 - "$REPO/start.sh" <<'PY'
import re, sys
txt = open(sys.argv[1], encoding="utf-8").read()
blk = re.search(r'declare -A SGLANG_OVERLAY_MAP=\((.*?)\n\)', txt, re.S).group(1)
for m in re.finditer(r'\[([^\]]+)\]=(\S+)', blk):
    print(f"{m.group(1)} {m.group(2)}")
PY
)
[ "${#PAIRS[@]}" -gt 0 ] || { echo "FAIL: parsed 0 overlay mappings from $REPO/start.sh" >&2; exit 2; }

# --- 这个容器是什么形态？-----------------------------------------------------
IMG="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null)"
binds=$(docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$CONTAINER" 2>/dev/null \
        | grep -c '/sgl-workspace/sglang/' || true)
if [ "${binds:-0}" -gt 0 ]; then MODE=bind; else MODE=image; fi

# --- 三份哈希：宿主 overlay / 容器内 / 镜像内（各自一次调用，不做 41 次 exec）----
names=(); paths=()
for p in "${PAIRS[@]}"; do
  f="${p%% *}"; hf="$REPO/sglang-overlay/$f"
  [ -f "$hf" ] || continue
  names+=("$f"); paths+=("/sgl-workspace/sglang/${p#* }")
done
# ★宿主的比对项也要按**目标路径**（不是源文件名）落表：容器/镜像两侧用的是目标路径，
#   混用两套键会让 41 个文件全部对不上（报成 41 个 MISSING，看着像"容器里没有这些文件"）。
hash_host() { local i=0; while [ "$i" -lt "${#names[@]}" ]; do
    printf '%s\t%s\t%s\n' "$(sha256sum "$REPO/sglang-overlay/${names[$i]}" | cut -d' ' -f1)" "${paths[$i]}" "${names[$i]}"
    i=$((i+1)); done; }
hash_cont() { docker exec "$CONTAINER" sha256sum "${paths[@]}" 2>/dev/null | awk '{print $1" "$2}'; }
hash_img()  { docker run --rm --network none --entrypoint sha256sum "$IMG" "${paths[@]}" 2>/dev/null | awk '{print $1" "$2}'; }

[ "$QUIET" = 1 ] || echo "container: $CONTAINER   image: $IMG   形态: $MODE（$binds 个 overlay bind）  文件: ${#names[@]}"
HOSTH="$(hash_host)"; CONTH="$(hash_cont)"
IMG_MISSING=0
if [ "$MODE" = image ]; then IMGH="$(hash_img)"; [ -n "$IMGH" ] || IMG_MISSING=1; fi

same=0; drift_hc=0; drift_hi=0; missing=0
while IFS=$(printf '\t') read -r hh dst f; do
  [ -n "$dst" ] || continue
  ch=$(printf '%s\n' "$CONTH" | awk -v d="$dst" '$2==d{print $1}')
  ih=$(printf '%s\n' "${IMGH:-}" | awk -v d="$dst" '$2==d{print $1}')
  if [ -z "$ch" ]; then
    missing=$((missing+1)); echo "MISSING  $f   (容器内读不到 $dst)"
    continue
  fi
  if [ "$hh" = "$ch" ]; then
    same=$((same+1)); [ "$QUIET" = 1 ] || echo "same     $f"
  else
    drift_hc=$((drift_hc+1))
    echo "DRIFT    宿主↔容器  $f"
    printf '           host      %s\n           container %s   <- 在役进程读的是这些字节\n' "${hh:0:16}" "${ch:0:16}"
  fi
  # image 模式再单列一类：容器内那份与**镜像**不同 ⇒ 有人在容器可写层里就地改过（重启即丢）
  if [ "$MODE" = image ] && [ "$IMG_MISSING" = 0 ] && [ -n "$ih" ] && [ "$ih" != "$ch" ]; then
    drift_hi=$((drift_hi+1))
    echo "DRIFT    镜像↔容器  $f（容器内那份被就地改过，镜像里没有；重启即回退）"
  fi
done <<< "$HOSTH"

echo
echo "same=$same drift(宿主↔容器)=$drift_hc drift(镜像↔容器)=$drift_hi missing=$missing"
if [ "$drift_hc" -gt 0 ] || [ "$missing" -gt 0 ] || [ "$drift_hi" -gt 0 ]; then
  if [ "$MODE" = bind ]; then
    echo "VERDICT: 在役容器读到的**不是**盘上 overlay 的这一份（bind 模式）。"
    echo "         逐文件 bind 钉住 inode ⇒ 盘上的改动在容器里是惰性的。"
    echo "         处置：开窗**重建容器**（JIT 缓存会自我失效，改头文件无需手工步骤）。"
  else
    echo "VERDICT: 在役容器读到的**不是**盘上 overlay 的这一份（image 模式，代码来自镜像）。"
    echo "         ★处置：**重建镜像并分发**（改镜像里的那份），而不是重建容器 ——"
    echo "           容器重建只会再读一遍同一个镜像，盘上的改动依然进不去。"
    echo "         逐机核对：bash <交付目录>/verify_image.sh $IMG"
  fi
  exit 1
fi
if [ "$MODE" = bind ]; then
  echo "VERDICT: 容器视图 == 盘上 overlay（$same 个文件）。"
else
  echo "VERDICT: 容器视图 == 盘上 overlay == 镜像（$same 个文件，形态=image）。"
fi
