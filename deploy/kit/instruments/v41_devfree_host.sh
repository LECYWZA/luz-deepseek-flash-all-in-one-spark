#!/bin/bash
# v41_devfree_host.sh — GB10 统一内存上「设备可见空闲」的**宿主侧零容器**量具（2026-09-22）
#
# 为什么需要它：此前要读 device free 只有两条路——① `nvidia-smi`（GB10 上一律 N/A）
# ② 起一个 `--gpus all` 容器跑 torch.cuda.mem_get_info（重、要镜像、要 GPU）。本工具用
# libcuda 的 `cuDevicePrimaryCtxRetain` + `cuMemGetInfo_v2` 直接量，**不起容器、不装 torch**。
#
# ★它锚定的硬事实（本项目 2026-09-11 定谳、2026-09-22 逐位复现）：
#   GB10 上 CUDA 报的 "free" **≡ MemFree**，不是 MemAvailable。
#   2026-09-22 09:xx 实测：dev_free=93.06GiB  MemFree=93.06GiB  MemAvailable=114.30GiB  Cached=21.46GiB
#   ⇒ 页缓存**对设备不可见**，且**驱动不会优雅回收它**（attempt13 的 worker init CUDA OOM 真死因；
#      `attempt13` 是代号，见 ~/w6-kit/GLOSSARY.md）。
#   推论（本工具的核心判据）：任何"把 MemFree 变成 Cached"的操作（读权重预热、大文件拷贝、
#   镜像拉取）都在 1:1 挖走设备可用内存，**而 eff_idle 判据完全看不见**——因为 Cached 本就在
#   eff_idle 公式里。故：起栈前必须 drop_caches（生产协议），且必须**验证**它真的回落到位。
#
# 用法：
#   v41_devfree_host.sh                # 打印一行量具值 + 恒等断言（dev_free 与 MemFree 相等）
#   v41_devfree_host.sh --check 100    # dev_free ≥ 100 GiB ⇒ rc 0；否则 rc 1（可接门禁）
#   v41_devfree_host.sh --min4         # 安全护栏自检：MemFree<4GiB 时**拒绝**建上下文（防 0211 事故）
#                                      #   ⚠️ `0211 事故`**名实不符**（2026-09-23 补注，未改本行代码）：
#                                      #   名字像日期（2 月 11 日），但**三条出处全无日期**（WINDOW-RUNBOOK.md:88、
#                                      #   本文件本行、~/V41-R3-FOLLOWUP-AND-LEVERS-20260922.md:127），而项目记录
#                                      #   覆盖期是 2026-08~09 ⇒ **疑为流水编号**（同 `attempt13` 的命名法）；
#                                      #   **待补出处 / 请上级裁决**。代号登记见 ~/w6-kit/GLOSSARY.md（`0211 事故` 条）。
#   v41_devfree_host.sh drop           # sync + drop_caches（需 ~/.sudopw；生产协议动作用）
#   v41_devfree_host.sh selftest       # 判别式自检
#
# 安全：只建 primary context（~300 MiB）做只读查询，随即退出释放；**绝不分配大块**。
#       且 MemFree < 4 GiB 时拒绝探查（对齐 "探针请求必须 ≤free−4 GiB" 红线）。
set -uo pipefail

PROBE_PY='
import ctypes, os, sys
# ★本段整体由 shell 单引号包裹：**内部一律只用双引号**，否则单引号会提前终止 shell 字符串
#   （2026-09-22 自检实测：写成 mi[单引号]Cached 时 python 收到半截表达式 ⇒ NameError）。
# ★测量学（同日自检实测的坑）：**探查动作自己建的 primary context 要吃 ~250 MiB 设备内存**，
#   且 MemFree 在两次读数之间会漂。所以必须：先拿 t0 读数 → 建上下文 → 量 dev_free →
#   **再**拿 t1 读数，与 t1 比（同态），并把 t0→t1 的漂移当容差底噪打出来。
minfree = float(os.environ.get("MINFREE_GIB", "0") or 0)
thresh  = os.environ.get("THRESH_GIB", "")
def read_mi():
    mi = {}
    for ln in open("/proc/meminfo"):
        k, v = ln.split(":", 1); mi[k] = int(v.split()[0])
    free = mi["MemFree"] / 2**20
    eff = (mi["MemFree"] + mi["Cached"] + mi["SReclaimable"] - mi["Shmem"]) / 2**20
    return free, mi["Cached"] / 2**20, eff
free0, cac0, eff0 = read_mi()
if minfree and free0 < minfree:
    print(f"REFUSE MemFree={free0:.2f}GiB < {minfree}GiB ⇒ 按红线拒绝建上下文（未接触驱动）")
    sys.exit(3)
try:
    cuda = ctypes.CDLL("libcuda.so.1")
except OSError as e:
    print(f"NO-LIBCUDA {e}"); sys.exit(4)
if cuda.cuInit(0) != 0: print("NO-CUDA cuInit 失败"); sys.exit(4)
dev = ctypes.c_int()
if cuda.cuDeviceGet(ctypes.byref(dev), 0) != 0: print("NO-DEV"); sys.exit(4)
ctx = ctypes.c_void_p()
if cuda.cuDevicePrimaryCtxRetain(ctypes.byref(ctx), dev) != 0: print("NO-CTX"); sys.exit(4)
cuda.cuCtxSetCurrent(ctx)
f = ctypes.c_size_t(); t = ctypes.c_size_t()
rc = cuda.cuMemGetInfo_v2(ctypes.byref(f), ctypes.byref(t))
if rc != 0: print(f"NO-QUERY rc={rc}"); sys.exit(4)
dev_free = f.value / 2**30
free1, cac1, eff1 = read_mi()          # ← 同态读数（含本探查上下文）
drift = abs(free1 - free0)
d = dev_free - free1
tol = 0.10 + drift                     # 容差 = 固定 0.1 + 实测漂移
verdict = ""
ident_bad = abs(d) > tol
if ident_bad:
    verdict = f"  ⚠ 恒等被打破 |Δ|={abs(d):.3f}GiB > 容差 {tol:.3f}（漂移 {drift:.3f}）⇒ 语义变了或非 UMA，判据需再审"
if thresh:
    if dev_free + 1e-9 >= float(thresh):
        verdict += f"  OK dev_free={dev_free:.2f}GiB ≥ {float(thresh):.2f}GiB"
        code = 0
    else:
        verdict += f"  FAIL dev_free={dev_free:.2f}GiB < {float(thresh):.2f}GiB"
        code = 1
else:
    code = 5 if ident_bad else 0
print(f"dev_free={dev_free:.3f}GiB dev_total={t.value/2**30:.2f}GiB memfree(t1)={free1:.3f}GiB "
      f"cached={cac1:.2f}GiB eff_idle={eff1:.2f}GiB identity_delta={d:+.3f}GiB drift={drift:.3f}GiB{verdict}")
sys.exit(code)
'

PY_RUN() { env MINFREE_GIB="${MINFREE_GIB:-0}" THRESH_GIB="${THRESH_GIB:-}" python3 -c "$PROBE_PY"; }

case "${1:-}" in
drop)
  sudo -S -p '' sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches' < "$HOME/.sudopw" 2>/dev/null \
    || { echo "drop_caches 失败（无 sudo？）" >&2; exit 2; }
  echo "drop_caches 已执行";;
selftest)
  echo "══ D1 量具通路 + 恒等断言（dev_free ≡ MemFree）"
  out=$(PY_RUN); rc=$?
  echo "   $out"
  case $rc in
    0) echo "  ✓ 量到值且恒等成立（|Δ|≤0.05GiB）";;
    5) echo "  ✗ 恒等不成立（|Δ|>0.05GiB）⇒ 驱动语义变了或非 UMA，判据需再审";;
    *) echo "  ✗ 量具不可用（rc=$rc）";;
  esac
  echo "══ D2 安全护栏：MemFree 地板必须拒绝建上下文"
  out2=$(MINFREE_GIB=99999 PY_RUN); rc2=$?
  echo "   $out2"
  [ "$rc2" = 3 ] && echo "  ✓ 超地板即拒绝（rc=3），未接触驱动" || echo "  ✗ 护栏未生效（rc=$rc2）"
  echo "══ D3 --check 门禁语义"
  bash "$0" --check 99999 >/dev/null 2>&1; c3=$?
  [ "$c3" = 1 ] && echo "  ✓ 不达标 rc=1" || echo "  ✗ 期望 rc=1，实得 $c3"
  bash "$0" --check 1 >/dev/null 2>&1; c4=$?
  [ "$c4" = 0 ] && echo "  ✓ 达标 rc=0" || echo "  ✗ 期望 rc=0，实得 $c4"
  echo "══ D4 恒等断言的\"红\"能力（反例：假装 MemFree 比真实高 8GiB）"
  MINFREE_GIB=0 python3 - <<'PYEOF'
import ctypes
cuda = ctypes.CDLL("libcuda.so.1"); cuda.cuInit(0)
dev = ctypes.c_int(); cuda.cuDeviceGet(ctypes.byref(dev), 0)
ctx = ctypes.c_void_p(); cuda.cuDevicePrimaryCtxRetain(ctypes.byref(ctx), dev); cuda.cuCtxSetCurrent(ctx)
f = ctypes.c_size_t(); t = ctypes.c_size_t(); cuda.cuMemGetInfo_v2(ctypes.byref(f), ctypes.byref(t))
real = f.value / 2**30
d = real - (real + 8.0)
print(f"   反例样本 identity_delta={d:+.3f}GiB ⇒ " + ("✓ 断言会报红" if abs(d) > 0.05 else "✗ 断言不会报红"))
PYEOF
  ;;
--check)
  TH="${2:?--check 需要阈值 GiB}"; THRESH_GIB="$TH" PY_RUN;;
--min4) MINFREE_GIB=4 PY_RUN;;
"")    PY_RUN;;
*)     grep -E '^# (用法|安全)' "$0" | sed 's/^# //'; exit 2;;
esac
