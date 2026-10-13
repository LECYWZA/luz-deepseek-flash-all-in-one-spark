# R1-FP4KV 设计卡：SM120 sparse-MLA 内核内直读 288B fp4 池（0.3.1 W3 槽·冻结版）

> 产出：R1 设计卡环节（总卡 §十九 W3 行：P1 定上限→**设计卡冻结**→实现批→探针窗）。
> 用户裁定③法源：「对于FP4kv的优化路线，选择R1获得最佳性能」（总卡 §十九 :413）。
> 纪律：本卡为**纯案头设计件**，零集群操作、零代码改动；社区仓/sglang-main-src/我方在役件
> 全程只读。一切数字给证据锚点（文件:行）；推测显式标注「推演级」。
> 收益口径：128k 档 ms/chunk（基线墙 866ms=45 键锚 4661.9 tok/s；现役产线=47 键
> 99e7ec92+overlay o12c1-prod，判读线=探针窗成对差分非绝对锚）。

---

## 〇、法源与在役件锚点（含 md5，防漂移）

| 件 | 路径 | md5 | 用途 |
|---|---|---|---|
| 定谳件（R1 定义法源） | docs/research/COMMUNITY-GAP-VERDICT-20261010.md §2.1+§丙 | —（cf4be7d 提交） | 四路定谳+R1 定义+P1 前置 |
| 队列上下文 | docs/taskcards/PREFILL-FIX-CAMPAIGN-CARD-20261009.md §十九 :409-456 | — | 0.3.1 W0-W11 重排；W3=本卡 |
| accept 口径学基件 | 同上 §十六 :303-309 | — | GSM8K 级预热后采样；绝对带 [2.90,3.30] |
| 社区先例（NVFP4 内核内直读） | ~/knapcio-v41-audit-20260925/runtime/b12x_next/b12x_next/attention/_shared/mla/prefill_mg.py | c941433a1d97ff6a5def9bc32c1b69df | :869-941 反量化；:915-981 s1 NVFP4 |
| 社区反量化原语库 | 同树 _shared/mla/decode_math.py（:1447-1531）+ _lib/intrinsics.py（:4541/:4792/:2944） | — | 指令序列法源 |
| 我方桥（在役） | ~/migrate-assets/dsv41/adapter/kv_fp4.py | 954cab11d611e548fea22baa8b2f7386 | :322-412 桥位置 |
| 我方 repack（在役） | ~/migrate-assets/dsv41/adapter/kv_fp4_repack.py | 060be9938108cfe75741cc6f8a347011 | 核 :268-349；ref :525-625 |
| flashinfer JIT 源（参照树） | ~/w6-kit/fi016-src（flashinfer **0.6.16**，git 8da13a29） | 见 §3.2 | sparse_mla_sm120 全套 .cu/.cuh |
| 我方入口（在役 sglang main） | ~/sglang-main-src/python/sglang/kernels/ops/attention/flash_mla_sm120.py | — | :215-267 prefill/:283+ decode 分发 |
| census | logs/M12FORMAL-20261005/census/M12F_TXL128k_census_cpr.json | — | repack/sparse 两族读数 |

**锚点勘误一条**：定谳件 §庚写「kv_fp4.py:199-200=docstring 自认 in-kernel read 路」——亲核后该
docstring 实位于 **kv_fp4_repack.py:199-200**（"reading the fp4 pool in-kernel (upstream FlashInfer
#5197) which deletes the write entirely"）；kv_fp4.py:199-200 是另一 installer。语义不变，锚点更正。

---

## 一、目标与非目标

### 1.1 目标（整删面）
1. **整删独立 repack 核的 prefill 面调用**：`repack_fp4_to_v4_kernel`（M12F census 第 2 大族
   101.82ms/step=14.9%、54.5 calls/step、1.868ms/call、us_max 4.7ms；锚点尺度 114.6ms/chunk）在
   prefill 相归零——由 sm120 sparse-MLA prefill 核获得 **288B fp4 池行原生消费变体**（内核内
   E2M1×E4M3 反量化），scratch 中转与查询切片一并消失。
2. **流量结构**：repack 族自身 872B/行（读 288+写 584）→0；注意力核 extra 段读 584B/行→288B/行。
   全链 DRAM/行=288(repack 读)+584(repack 写)+584(注意力读 scratch)=**1456B→288B（5.06×）**
   （repack 族单看 3.03×；「~3×」为定谳件保守口径，全链账更优——推演级，SMEM/L2 二阶不计）。
3. **收益上限=P1 暴露量（参数化，见 §1.4）**：闭合模型已证重叠率 ≥50.5% 强制成立（全暴露预测墙
   924>实测 866，定谳件 §A2），可回收的墙时间=非重叠暴露量（预测带 [29,81]ms 中枢 55），**非**
   内核和 114.6ms。P1 实测=空位（W-optD 收窗相位产出，§八回填）。
4. 顺带产物：prefill 查询切片消失（62.4→~21 calls/step 形状，§2.3）；桥 scratch 预算
   （512MiB+ids 8MiB）在 prefill 面释放；R3 零行填充面被吸收（§8.2）。

### 1.2 非目标（明示不做）
- **decode 面**：0.53ms/step（定谳件 §2.1；勘误 #5）——不值得内核级改造；decode 走 CUDA graph，
  换核另有捕获互作面。decode 维持现役 repack 桥原样（回退路径同时在役，见 §3.8）。
- **池布局改版（R4）**：容量红维持死刑（8.16GiB→14.8GiB ×1.81 跌破 600k×16 标准形，定谳件 §2.1）。
  288B V41_FP4 池行格式与写入器**零改动**。
- **R2 切片流水 / R3 变长 gather**：总卡 §十九 W3 行已定谳弃路（R1 上位形直达）；R3 占用率测量
  已并入 W1 前置 record-only。
- **V-B 保真形**（§3.5）：改变 nope 通道数值语义，非本窗目标（0.3.2+ 可议，须全质量门重定基）。

### 1.3 判读基线
探针窗成对差分（同窗基线臂 vs R1 键臂，47 键基座+overlay o12c1-prod 同件两靴）；绝对锚仅参考
（C0 锚位位移 −2.1% 悬置在册，总卡 §十七）。

### 1.4 收益三档表（参数化于 P1；待 W-optD 终报回填实值）
模型：回收墙时间 ≈ P1（R1 后注意力核 extra 段字节面反缩 584→288B/行，dequant ALU 为新增但
带宽主导面占比极小——推演级无抵消项；下界=P1−注意力核增长，增长推演为负或零）。

| P1 档 | 回收 ms/chunk | 866ms 墙推演 | tok/s 推演（对 4661.9 锚） | 判级 |
|---|---|---|---|---|
| 下沿 29 | 29 | 837 | ≈4823（+3.5%） | 探针窗成对 ≥+1.5% 门远超 |
| 中枢 55 | 55 | 811 | ≈4978（+6.8%） | 同上 |
| 上沿 81 | 81 | 785 | ≈5142（+10.3%） | 同上 |
| （空位）P1= | | | | §八回填 |

- 若 **P1 实测≈0**（重叠率→100%）：R1 墙收益塌零 ⇒ 降级为卫生件（census 形状证+水位释放+调用数
  下降），呈裁是否仍落。此分支判读预登记，防事后改线。
- 三档均按 45 键锚 4661.9 算；探针窗实测以当窗成对基线为准（47 键基座预期 ~4825，W-optD D0 实测）。

---

## 二、现状桥解剖

### 2.1 桥调用图（在役形，kv_fp4.py md5 954cab11）
```
引擎注意力层（sparse-MLA 层，~21 层/step）
 └─ sglang.kernels.ops.attention.flash_mla_sm120.flash_mla_with_kvcache_sm120  ← 模块属性被 kv_fp4.py:322-412 包裹
     ├─ extra is None / 非 fork-v4-fp4 / extra.shape[-1]!=288 → 原样透传 orig（:323-327）
     ├─ 非 sm120 平台 → fail-loud（:332-339）
     ├─ q.shape[0]>64（SM120_DECODE_MAX_TOKENS，flash_mla_sm120.py:212）→ prefill 面：
     │    bridge_slice_bounds(q.shape[0], extra_topk)（kv_fp4.py:350-351；kv_fp4_repack.py:383-395）
     │    对每切片：repack_fp4_extra_to_v4(extra, extra_indices[lo:hi], src_page_size)（kv_fp4_repack.py:398-522）
     │      ├─ Triton _repack_fp4_to_v4_kernel[(n,)]（:268-349）或 CUDA .so（:505-508；auto=按 n 分派）
     │      └─ 产出：V4 scratch 视图 (P,64,1,584) + 恒等索引 ids
     │    orig(**kwargs 切片, extra_k_cache=scratch, extra_indices_in_kvcache=ids)（kv_fp4.py:375-399）
     │      └─ _flash_mla_sm120_prefill（flash_mla_sm120.py:215-267）
     │          └─ flashinfer _sparse_mla_sm120_paged_attention（fi016 _sparse_mla_sm120.py:403-508）
     │              └─ sparse_mla_prefill_dispatch → dispatch_dsv4_dual（prefill.cu:310-401，topk=128 专属）
     └─ q.shape[0]≤64 → decode 面：同一 repack 路（单切片）→ _flash_mla_flashinfer（:583-675，split-K mid_out）
```
- repack launch **无 stream 参数**（kv_fp4_repack.py:505-517）：随当前流串行——R2 的定谳依据，R1 使其
  在 prefill 面整体不存在。
- scratch 生命周期：grow-only 持久缓冲（kv_fp4_repack.py:352-373），CUDA graph 捕获兼容。

### 2.2 288B fp4 池行 vs 584B V4 scratch 逐字段对照
源=KVLayout.V41_FP4 页（kv_fp4_repack.py:57-60 常量 + Triton 核 :277-300 寻址；页=数据区+尺度区
分离）：页内 `[page_size×256B 数据][page_size×32B 尺度]`，行=数据区 `slot*256` 起 256B，尺度区
`page_size*256 + slot*32` 起 32B。

| 字段 | 288B fp4 池行（源） | 584B V4 scratch 行（现核消费形） | 转换 |
|---|---|---|---|
| k_nope 448 值 | 载荷字节 [0,224)，每字节 2×E2M1 nibble（低偶高奇，:296-302） | 数据行 [0,448) 每值 1×E4M3 字节，576B 行距（:69/:322-325） | E2M1×E4M3→fp32 精确→**按 64 值 tile requant** E4M3×UE8M0（:306-321） |
| k_rope 64 值 | 载荷字节 [224,256)，同为 E2M1 nibble 对（:327-335） | 数据行 [448,576) 每值 bf16（=128B） | E2M1×E4M3→fp32 精确→bf16（**精确，无损**） |
| 组尺度（fp4 侧） | 尺度区 32B=32 组×16 值 E4M3（组 g=值 //16；nope 用 0-27，rope 用 28-31，:299/:333） | —（被 requant 吸收） | 每 16 值组一个 E4M3 字节 |
| tile 尺度（V4 侧） | — | 页脚尺度块 @页偏 36864 起 8B/token=7×UE8M0+1 pad（:71-72/:341-349） | `ue8m0 = biased_exp(max(amax,1e-4)/448) + (mant≠0)`；幂二互逆乘精确（:311-318） |
| 页几何 | pbs=256（ratio-1）/128（ratio-2），页距=步长(0) | pbs=64，页 37440B，584B 视图仅 FFI 传递形（:61-67） | 行 j → 页 j//64 槽 j%64 恒等（:443-465） |
| 非法槽（-1/stale） | 索引位 -1 | 零载荷行+地板 ue8m0≈105（host sanity §4.2 D 核） | gate=0 乘（:282-291）；核内以 topk_length/-1 掩蔽同效 |

内核侧消费（fi016 prefill_kernel.cuh，BF16 计算形=产线形，§3.1）：smem 暂存 **原始 E4M3 字节**
（KV_SMEM_STRIDE=464，kv_cache_traits.cuh:126），math warp 在 B 操作数生产点逐对反量化
`cvt.rn.f16x2.e4m3x2 → ×scale_f(UE8M0→f32) → cvt.rn.bf16x2.f32`（prefill_kernel.cuh:942-985，
MG 双组共享一次反量化）；rope 为 gmem bf16 直读+预取（:930-931，q_rope/xv_rope_mma 两消费点）。

### 2.3 调用频度账（census 自洽反推，推演级）
- 桥 scratch 预算=512MiB→`bridge_max_rows`=536870912//37440×64=**916,928 行**（kv_fp4_repack.py:376-380）。
- 128k chunk=4096 token×extra topk 512=2,097,152 行>预算 ⇒ `step=916928//512=1790` token/切片→
  **3 切片/chunk**（:383-395）。
- sparse_mla 族 62.4 calls/step ÷3≈20.8≈21 稀疏层/step ✓；repack 54.5 calls/step（<63=21×3，
  差额=ramp 2 步+尾 3 步小 token 数切片数少的混匀，census 38 步口径）✓。两族比值 54.5/62.4=0.873
  与「桥只在带 extra 的层发火」自洽。
- us_max 4.7ms≈满切片 917k 行×872B≈0.80GB/245GB/s≈3.3ms+尾（带宽地板 245/273GB/s≈90% LPDDR，
  定谳件 §2.1 由 calls/step 与数据量独立反推）⇒ **无内核内优化空间，只有结构路**（法源结论）。
- decode 面 0.53ms/step：decode 批 ≤64 token×512=32,768 行≪预算单切片（:385-389）。

---

## 三、R1 内核设计

### 3.1 选核结论（census 定优先级）
两入口收敛于同一 flashinfer 分发器 `_sparse_mla_sm120_paged_attention`（fi016
_sparse_mla_sm120.py:403-508），内部分流：
- **prefill 入口**（q.shape[0]>64→`_flash_mla_sm120_prefill`→`dispatch_dsv4_dual`，prefill.cu:310）：
  census 主面（repack 101.82 vs decode 0.53 ms/step，191×差）⇒ **先改且只改此入口**。
- **decode 入口**（≤64→`_flash_mla_flashinfer` split-K，:583-675）：不动（非目标 §1.2）。
- 产线形落点：`dispatch_dsv4_dual` 仅支持 **topk(main)=128**（prefill.cu:374 `if (topk != 128)
  return false`——产线今日成功分发即证 topk=128）且**全部走 ComputeMode::BF16**（topk=128 无
  topk_length 时 fulltile 臂优先 BF16；带 topk_length 走 DISPATCH_BY_NH_PBSX=BF16 全 NH，
  prefill.cu:360-372）。⇒ R1 变体只需覆盖 **DSV4 双缓存×BF16×topk128×NH{16,32,64,128}×
  extra pbs{128,256}** 组合——分发面收窄，工作量受控。
- extra pbs 现分发仅 {64,2}（prefill.cu:323/:364-371；今日=scratch 的 64）；R1 须增 {128,256}
  实例化（池原生页，由 FFI 从张量元数据取步长，_sparse_mla_sm120.py:337-339 同机制）。

### 3.2 基底选择（呈裁已定推荐 A）
- **A（推荐）：flashinfer JIT 源 fork，独立 JitSpec 名**。参照树=fi016-src（flashinfer 0.6.16，
  git 8da13a29；关键件 md5：sparse_mla_sm120_prefill.cu=561e114b5e19d0370c0011e03dea5dec、
  prefill_kernel.cuh=03b668b385fd6dee0df6c652b47d9f1e、kv_cache_traits.cuh=c15583ac305acbc431ebf5940bea535b）。
  内核为 nvcc JIT 编译（flashinfer/jit/mla.py:35-49 `gen_sparse_mla_sm120_module`→
  data/csrc 5 个 .cu+data/include 头）。fork 形=adapter 自带源目录+**新模块名**（如
  `sparse_mla_sm120_fp4`）JIT 构建：不触碰产线已装 flashinfer 包、JIT 缓存名空间隔离、键关即
  整路消失（回退=现役形逐位，构造性）。
- **A'（实现批 T0 精读项，可降级工作量）**：上游新线已出原生面——flashinfer 2026-09 release
  highlights 载「DeepSeek-V4 Flash sparse MLA supports an NVFP4 KV cache on SM120/SM121 through
  `kv_cache_format="nvfp4"`」（PR #4955 feat(sm120): add NVFP4 sparse MLA；另有 #3640 SM120
  NVFP4 attention JIT）。若其消费布局=我们 288B 行（fp4 rope+页分离尺度）则退化成**升级+适配
  接线**；若是社区 432B 记录形（bf16 rope，prefill_mg.py:107-115）则 fork 上游 NVFP4 核改寻址
  仍优于从零写 V-A。定谳件所称「上游 #5197」离线未能索引核verify（web 检索无此号；#4955/#3640
  为可锚替代）——T0 以镜像内可得版本亲核定案。
- **B（否决）：移植社区 b12x_next CuTe DSL 核**。虽同型且产证（5392 tok/s 零 repack），但其
  DSL 核拖着 _lib/intrinsics+compiler 整套自有基建，sglang 栈内无此依赖面；移植面≫fork 面；
  留作 A 性能不达标时的对照参照（其指令序列仍是本卡反量化法源）。

### 3.3 288B 行加载模式（extra 段 IO）
沿用核内既有 footer 页寻址律（主缓存 DSV4 页=数据区+页脚尺度区，kv_cache_traits.cuh:108-121；
fp4 池同构不同几何）：
```
idx（extra_indices 原始槽 id，-1=跳过——FFI 原生语义 _sparse_mla_sm120.py:441-442）
page  = idx >> PBS_BITS；slot = idx & (pbs-1)        # pbs∈{128,256}，运行期步长(0)
行载荷 = pool + page*stride0 + slot*256              # 256B 连续=224B nope+32B rope（16B 对齐 ✓）
组尺度 = pool + page*stride0 + pbs*256 + slot*32     # 32B；nope 组 0-27 / rope 组 28-31
```
- 每 entry 两段取数（256B 连续+32B 尺度）vs 今日 448B 数据+8B 页脚——IO 字节面反缩。
- 每线程作业粒度=**1 个 64 值 tile**（32B 载荷+4B 尺度组×4…实为 1 尺度字节/16 值→tile 内 4 字节）：
  448 nope tile 作业+64 rope 作业每 KV tile（BI=64 行），128 IO 线程摊 4.5 作业/线程（推演级）。

### 3.4 寄存器 E2M1×E4M3 反量化序列（对照社区先例逐指令映射）
社区原语（intrinsics.py，SM120a inline PTX，产线在役同型）：
- `fp4_decode_2`（:4792-4810）：`cvt.rn.f16x2.e2m1x2`——1 字节 2×E2M1→f16x2。
- `cvt_e4m3_to_f32_via_f16`（:4541-4560）：`cvt.rn.f16x2.e4m3x2`+f16→f32——E4M3 尺度字节→f32。
- `nvfp4_pair_to_bf16x2_sm120`（:2944-2968）：`cvt.rn.bf16x2.e2m1x2`+`cvt.rn.bf16x2.e4m3x2`+
  `mul.bf16x2`（PTX 9.2）——注：「Every finite E2M1 × E4M3 product is exactly representable in
  BF16」（host sanity §4.2 A 穷举 4064 对证实，fp16/bf16 双精确）。
- 社区 s1 消费点 `s1_qk_nope_nvfp4_bf16_mg2`（prefill_mg.py:915-981）：B 操作数对
  `b0/b1 = _nvfp4_pair_bfloat2_mg(base, row, ko+2*tid / +8, ...)`=读 1 载荷字节+1 尺度字节→
  decode→×scale→pack bf16x2；其 fp8 原型自认「Byte-for-byte mirror of FlashInfer
  prefill_kernel.cuh:883-932」——**即我方在役核 :942-985 同一代码位**（§2.2 末段）。
  逐指令映射表（我方核现 fp8 形 → R1 fp4 形）：

| 步 | 现（E4M3 输入，prefill_kernel.cuh:958-968） | R1（E2M1 输入，社区同型） |
|---|---|---|
| 取 B 对 | `ld.shared.u16 kv+ko+2*tid`（2 字节） | `ld.shared.u8 fp4+(ko+2*tid)/2`（1 字节）+`ld.shared.u8 scale[256+(ko+2*tid)/16]` |
| 载荷解码 | `cvt.rn.f16x2.e4m3x2` | `cvt.rn.f16x2.e2m1x2`（fp4_decode_2 同型） |
| 尺度 | UE8M0→f32（per-64 tile，kv_scale_buf） | E4M3→f32（per-16 组，cvt_e4m3_to_f32_via_f16 同型） |
| 乘+pack | `f32×scale → cvt.rn.bf16x2.f32` | 同形（保真形）；位等形先过 §3.5 requant 复刻步 |
| 尺度频度 | 每 64 值 1 字节 | 每 16 值 1 字节（4×加载，smem 廉价；可 per-16 提升 hoist） |

- rope 消费点两处（QK-rope MMA B 操作数+XV-rope FMA）：fp4 rope 直解=E2M1×E4M3→bf16（精确，
  §4.1-B）——替代今日 gmem bf16 直读；尺度组 28-31 自页尺度区。

### 3.5 值域变体两形（本卡核心裁定点）
**勘误级发现（对定谳件 §2.1「现 repack 也是 E2M1→高精度展开」的修正）**：现 repack 对 **nope 通道
并非纯高精度展开**——E2M1×E4M3 精确值后还有一步 **per-64-tile requant 到 E4M3×UE8M0**
（kv_fp4_repack.py:306-321 Triton 形；:583-591 ref 形；语义=复刻产线 store.cuh 写 V4 池的量化式，
使 fp4 boot 与 pre-fork fp8 池 KV 级逐字节不分，:15-24 docstring）。故「等价性构造性」仅对
rope 通道成立（bf16 容 6 位有效积，无损往返）；nope 通道等价须**在核内复现同一 requant**。

- **V-A 位等复刻形（本卡推荐，W3 落地形）**：IO 段每线程 tile 作业内两遍解码（推演级寄存器
  ~24-32/thread，输入 8×u32+输出 8×u32+杂项）：
  遍1 amax：32B→16×cvt.e2m1x2→fmax 累加（1 寄存器累加）→`ue8m0=biased_exp(max(amax,1e-4)/448)+
  (mant≠0)`（整数式，与 :311-318 逐位同）→遍2 发射：再 16×cvt→×inv（幂二精确）→
  `cvt.rn.satfinite.e4m3x2`→STS 到**与今日完全相同的 KV smem 形**（E4M3 字节 464 行距+页脚
  尺度 buf）→ **math warp 零改动**，注意力输出与现役形逐位相等（构造性，§4.1）。
  rope：消费点直解（§3.4）或 IO 段预产物 bf16——两形皆精确等价，推荐消费点直解（零 smem 增量）。
- **V-B 保真直解形（社区先例原样，缓议 0.3.2+）**：B 操作数 E2M1×E4M3→bf16 直喂 MMA，省
  requant 步与 amax 遍；数值上**移除** store.cuh requant 噪声（更贴模型真值——ratio-1/2 潜向量
  经模型 e2m1 舍入、V41_FP4 无损，kv_fp4.py:172-175）——但注意力输出**不与现役形位等**，全部
  质量门转为语义判读。W3 不做（判读门机械性优先）；留档为潜在保真增益相位。

### 3.6 寄存器压力/占用率推演（推演级）
- 核为 warp-specialized 一 CTA/SM：N_IO_WARPS=4+N_MATH_WARPS=8=384 线程，IO warp
  setmaxnreg.dec/math warp inc（kv_cache_traits.cuh:162-168；社区同契约 _IO_REGS=32/
  _MATH_REGS=232，prefill_mg.py:96-97）。
- V-A 全部新算术落 **IO warp**（tile 作业 ~24-32 活寄存器，两遍解码法，§3.5）——需将 IO 段
  setmaxnreg 预算从纯 cp.async 发行位（很低）上调至 ~40（社区 32 参照+裕量），math warp 232
  预算不动；总量在 warp-spec 契约内再平衡（launch bound 元数据，社区 :2248-2256 注记同型）。
- smem：V-A 产出写入今日同形 KV smem（464 行距）+同形尺度 buf——**净增量≈0**；V-B 反而缩
  （288B 行距<464）。约束面=MG smem TOTAL≤101376（99KB/块限，smem_layout.cuh:146-148）今日
  已满足，两形均不越。
- 占用率：一 CTA/SM 不变；IO 段新增 ALU（每行 ~512 cvt+~450 乘加，推演级）由双缓冲流水
  （loop_tiles 双 buf，prefill_mg.py:2666-2670 同型）掩盖——带宽面 288B/行远低于地板余量。

### 3.7 发射配置
- 沿用现核发射（fork 内不动）：grid=num_tokens（×replicate_h 若用），block=384，min_blocks_
  per_mp=1（warp-spec setmaxnreg 契约，社区 __call__ :2240-2257 同型注记）；**prefill 不入
  CUDA graph**（现役 eager 路径），无捕获互作。
- 唯一新模板参：EXTRA 尺度格式 NVFP4_E4M3 + extra pbs∈{128,256}；dispatch 表加 4 NH×2 pbs=8
  实例（§3.1 收窄面）。JIT 编译期实实例化数+8（nvcc 时间线性增，首次 boot 编译预算见 §六-5）。

### 3.8 caller 侧改造（kv_fp4.py 桥开关+scratch 保回退）
- 新键 `DSV41_FP4KV_R1_INKERNEL`（缺省关）：开→prefill 尺寸（q.shape[0]>64）fp4 调用改走
  fork 入口（**原始 extra 池 2D 视图+原始 extra_indices+extra_topk_length 原样透传**，无
  repack/无切片/无恒等索引）；关→现役桥路径**逐字节不动**（回退=现役形，构造性位等）。
- decode 尺寸调用不受键影响（恒走现役桥）——scratch/ids 缓冲保留在役。
- fail-safe 运行期对拍（A23-β 同律）：首 eligible prefill 块同输入双跑 fork vs repack+现核，
  `torch.equal` 输出+LSE；失配→一键回退现役桥并告警横幅（WFP8-A bf16 永久回退无害先例，
  总卡 §十六-2）。
- 平台门沿用：fork 入口前置 `get_platform().is_sm120`（kv_fp4.py:332-339 同式）+fork JIT
  构建失败→回退桥（fail-loud 一行横幅，_repack_backend 降级律 :163-176 同型）。

---

## 四、值等价面

### 4.1 逐点算术等价条件（V-A 形；oracle=现 repack 路径同输入输出）
| # | 量 | 现 repack 路（Triton :293-349） | R1 核内 V-A | 等价条件 |
|---|---|---|---|---|
| 1 | E2M1→值 | `_e2m1_code_to_fp32(nib)×scale`（fp32） | `cvt.rn.f16x2.e2m1x2`（f16 精确） | E2M1 值 f16 精确（≤3 位有效）⇒逐位同 |
| 2 | ×E4M3 组尺度 | fp32 乘 | f16/f32/bf16 乘任一 | 积≤6 位有效，三域皆精确（§4.2-A 穷举 4064 对）⇒逐位同 |
| 3 | tile amax | fp32 abs-max（64 值，IEEE） | f16 abs-max | 精确值上取 max 无舍入⇒逐位同 |
| 4 | ue8m0 | `max(amax,1e-4)/448` IEEE 除+位技巧（:311-316） | 同式整数位技巧 | 幂二域整数运算⇒逐位同（含零行地板 105，§4.2-D） |
| 5 | 互逆乘 | `(254-ue8m0)<<23` 位造 f32，×（幂二精确） | 同式 | 精确⇒逐位同 |
| 6 | E4M3 requant | `.to(tl.float8e4nv)`=cvt.rn.satfinite | `cvt.rn.satfinite.e4m3x2` | 同指令语义（RN-satfinite）⇒逐位同（含 448 饱和） |
| 7 | rope→bf16 | `().to(tl.bfloat16)`（:334-335） | `cvt.rn.bf16x2`（精确域） | 6 位有效积 bf16 精确⇒逐位同 |
| 8 | 非法槽 | gate=0 零行+地板尺度（§2.2 末行） | ~~索引 -1/超 topk_length 核内掩蔽（贡献零）~~→**〔2026-10-11 勘误，DIFFLOC F1 落线〕** extra 相位 idx<0=门控零行复刻（钳位读 slot0+组尺度门 0：±0 载荷+地板 ue8m0=105，分数 0 入分母）；超 topk_length 长度掩蔽；main 相位 ib<0 掩蔽保留=stock 对称 | ~~掩蔽行贡献恒零⇒输出逐位同~~→**〔勘误〕** 零行 V=0 使分子贡献零，但窗内零行分数=0 使**分母 +2^0=1/条**（幻影单位质量）⇒等价条件改「fork 对窗内 -1 复刻零行语义（分数 0 参与 softmax）」，掩蔽形反与产线分歧（R1-FP4KV-DIFFLOC-20261011 §四） |
| 9 | 下游 smem/MMA | math warp 读 V4 形 smem | **同形 smem、同代码**（§3.5） | 构造性逐位同（输出含 LSE） |
- V-B 形等价面（缓议档）：#3-6 步整体删除→nope 通道值=精确 6 位有效（≠现役 E4M3 requant 值）；
  rope 通道 #1-2-7 仍逐位同。**若 V-B 启用，oracle 必须换「直解参考」，禁用 repack 输出当 oracle**
  （C-2 假红同型教训，总卡 §十八-4）。

### 4.2 host sanity 实测（本卡产出；CUDA_VISIBLE_DEVICES="" 纯 CPU torch 2.14.1）
复刻 repack ref 算术（kv_fp4_repack.py:525-625 同式）+直解实现四面验证，全绿：
- **A 精确性穷举**：16 E2M1 码×254 有限 E4M3 字节=4064 对积，fp16 与 bf16 双域**全部逐位精确**
  （max|积|=2688=6×448）——§3.4 指令映射#2 的算术基础。
- **B rope 位等**：直解 E2M1×E4M3→bf16 vs repack ref rope 输出，四面（rand/zero/sat448/subnorm）
  逐位相等——rope 通道构造性等价实证。
- **C requant 逐位**：直解+requant 实现 vs repack ref，四面 nope 载荷+ue8m0 字节逐位相等——
  转换是**行局部纯函数**，可移核内的实证基础。
- **D 边界**：448 饱和面（tile amax 2688→scale_raw 6.0→ue8m0=129→payload 672 饱和截 448）；
  次正规面（scale=0x01=E4M3 次正规 2⁻¹²×0.5=2⁻¹³ 值路径正常）；零行=零载荷+**地板 ue8m0=105**
  （1e-4/448 的 ue8m0；载荷零⇒值零与尺度字节无关——产线语义保持，§2.2 对照表末行）。
  〔**10-11 验收修正**：零载荷=**值零 ±0.0**，字节面 0x00/0x80——E2M1 负 nibble 解码 -0.0，
  IEEE 符号传播 `-0.0×0=-0.0` ⇒ requant 字节 0x80，**在役内核同式同传播**（主会话亲核
  kv_fp4_repack.py:301-302+sanity 实证）；实现批 T4 一切零行断言按幅值位（`&0x7F==0`）或
  fp8 值域比较，**禁按字节全 0x00 断言**（必假红）；-0.0 进 MMA 贡献恒零（-0.0+x=x）输出
  不受影响。host sanity 已入库 `dev/r1-fp4kv/sanity_host.py`（12/12 断言四面绿；合成池
  scale 上界 127 排除 0x7F=e4m3fn NaN——NaN×0=NaN 会使地板失效=合成面伪影，生产量化器
  不产 NaN scale）〕

### 4.3 单测矩阵（实现批 T4 消费；比较器=同量化域律）
| 面 | 输入构造 | 断言 |
|---|---|---|
| zeros | 载荷全 0（尺度任意非 NaN） | 输出与 repack oracle 逐位；值全零 |
| 448 饱和 | 载荷全 0x66（+6.0）×scale 0x7E(448) | 饱和路径逐位（ue8m0=129、payload 0x7E） |
| 深次正规 2⁻¹³⁰ 级 | scale=0x01（2⁻¹²）×nibble 0x01（0.5）→2⁻¹³；及全零 nibble | 次正规值逐位；不产生 denormal 漂移 |
| 次正规边界 | scale 扫 0x00/0x01/0x02 段 | e4m3fn 语义（0x00=零）核内解码一致 |
| 随机面 | 全 16 码×254 尺度合成行 | 逐位（host §4.2-C 已绿的设备端复刻） |
| 负号面 | 符号 nibble 位 3 全覆盖（含 -0.0/-6.0） | 符号传播逐位（LUT sign 律 :564-567） |
| e2e 位等 | 真实形状合成池+索引（含 -1/短 topk_length） | fork vs repack+现核：out+LSE `torch.equal` |
- **比较器律（A23-β C-2 教训，总卡 §十八-4）**：一切比较在**同量化域**——oracle=repack 路径
  （同为 V4 字节/BF16 MMA 域）产出，禁拿 bf16 原象比量化回环；V-B 档换 oracle（§4.1 末）。

---

## 五、判读门（冻结式；事前登记，零事后改）
探针窗=R1 键臂 vs 同窗基线臂成对（47 键基座+overlay o12c1-prod 同件；判读统一挂=时钟落盘+
accept 新口径律+census V3.1 一靴一 census+水位三明治，总卡 §十九）：
- **G0 运行期零崩溃**：prefill 全链 e2e（含 128k/600k 深载）；fail-safe 对拍横幅=绿（首块
  torch.equal 通过）。
- **G1 值等价单测全绿**：§4.3 矩阵 host 全绿+设备端运行期对拍绿（fail-safe 未击发）。
- **G2 needle/qeval**：needle 8k/32k/600k 3/3；qeval 按窗卡口径（案头缺口则如实注记，先例
  总卡 §十六-2）。
- **G3 PR ②尺成对**：≥+1.5% 门参照（W-optC 先例 ×1.008 件线）；R1 预期三档 +3.5%~+10.3%
  （§1.4）远超门——出带下判读回 P1 实测对账。
- **G4 census repack 族归零核证**：断言形态=raw 内核名 `repack_fp4_to_v4_kernel`（cpr json:392）
  在 R1 臂 census **缺席**（prefill 相）；族名 `const_int_const_unsigned_char_long_int_long_`
  calls/step 54.5→0（解析器 md5 留痕律+族名级对比先对 raw 内核名，TOOL-ANCHORS.md:18）；
  顺带形状证：sparse_mla 族 calls/step 62.4→~21（切片消失，§2.3）；decode 相 repack 仍在
  （0.53ms 面，非目标）——断言限定 prefill 相窗口。
- **G5 键关位等**：R1 键关复原臂=47 键现役形逐位（回退路径=原桥代码零改动，构造性；产线横幅
  0 行核证）；红退线=键关复原四查绿。
- **G6 accept 口径**：GSM8K 级持续 decode 预热后采样（n500），绝对带 [2.90,3.30]；出带=对照
  点位记录不判红（§十六-4 口径学基件）；护栏=锚 sane ≥2.0+双采样极差 <10%。
- **G7 水位三明治**：prefill scratch 释放（512MiB 预算 grow-only 缓冲+ids 8MiB 不再增长）+
  fork JIT 模块显存驻留增量记录位。

---

## 六、风险台账
1. **内核工作量 vs W3 槽**：V-A 含 fork 分发/traits/IO 转换/双消费点 rope 解码/测试窗件——估
   案头实现批 3-5 人日（推演级；§七拆解后按 T 实测修正）。超限→**拆相位呈裁**（预登记）：
   相位 1=nope V-A+rope 消费点直解（本卡全量）；相位 2=V-B 缓议件剥离（已在 §1.2）；
   相位 3=decode 面（永缓，0.53ms）。
2. **sm120 ISA 约束**：`cvt.rn.f16x2.e2m1x2`（fp4_decode_2 同型）社区 SM120a 产线在役=可行证；
   V-A 全程 f16/f32 中转**不需** PTX 9.2 的 bf16x2 打包转换（V-B 才用 `cvt.rn.bf16x2.e2m1x2`/
   `e4m3x2`，缓议档连带缓议 ISA 面）；satfinite E4M3 转换在役核已用（fp8_quant.cuh 域）。
   缓解：若 e2m1x2 cvt 在 fork 目标 flags 下不可用→LUT/移位解码回退（host §4.2 证明算术域
   等价，性能小损，R1 结构收益不受损）。
3. **census 归零核证的量具面**：两版解析器族名漂移陷阱（const_int vs kv_repack_fp4，
   TOOL-ANCHORS.md:8/:18）——G4 断言锚 raw 内核名而非族名；census V3.1 助具窗内在场（W-optC
   已修复入库，总卡 §十七-窗内修复）。
4. **部署互作（overlay 合树序）**：fork=adapter 新文件+新 JitSpec 名，**零触碰** flashinfer
   python 层与 sglang 树⇒与 CG-β（W-optD）/stage2（W5）overlay 无文件冲突；adapter 集合指纹
   更替走装载窗 map 重算（C1-PROD-PROMO 同律，总卡 §十九）。基座合树序=探针窗开窗前置按当期
   产线形（W-optD 若已转正则含其形）。
5. **JIT 首编译 boot 时长**：新模块名=首靴 nvcc 全编（现役 sparse_mla_sm120 模块 5 .cu 的
   编译时长量级，分钟级；~/.cache/flashinfer 缓存后复用）——探针窗 OUTAGE 预算内消化；
   T0 核verify 镜像内 nvcc 工具链在位（现役模块本身即 JIT 产物=间接证据，直接核verify 一次）。
6. **V-A 新颖性**：IO 段两遍解码+requant 复刻在两参照库均无现成先例（社区=V-B 形直解；现核=
   E4M3 输入零转换）——缓解：算术已被 repack Triton 核（在役、t44 位等钉死）+本卡 §4.2 host
   四面逐位锚定；寄存器/流水推演给 §3.6，实现批 T1 后以单 tile 微基准校准（探针窗内）。
7. **P1=空位的收益塌缩分支**：§1.4 末行预登记（P1≈0→降级卫生件呈裁）。
8. **上游版本漂移**：参照树 fi016=0.6.16；产线镜像实装版本/md5=T0 首查项（§3.2 md5 表）；
   A' 路线（上游原生 NVFP4）若成立则本卡 fork 面整体收缩为适配接线——T0 出结论后呈裁更新。

---

## 七、实现批任务拆解（供实现代理直接消费；单文件 add+核 staged+中文 message）
| # | 任务 | 文件级 TODO | 自检红绿 | 提交 |
|---|---|---|---|---|
| T0 | 前置核verify（半天） | 产线镜像 flashinfer 版本/data 源 md5 对照 §3.2 表；nvcc 在位+JIT 缓存路径；精读上游 #4955/#3640 与 release notes 的 NVFP4 布局（A' 可行性结论+呈裁） | 核verify清单落档（绿=md5 对上或 A' 定案） | notes 追记本卡 §3.2 |
| T1a | fork 头件 | `~/migrate-assets/dsv41/adapter/fi_r1/include/fp4_extra_traits.cuh`：288B 布局常量（§3.3 寻址）+tile 两遍解码转换函数（§3.5 遍1/遍2，指令序列 §3.4 表）+rope 直解 helper | host 编译通过+§4.3 矩阵可挂（暂以 host 参考壳驱动） | T1a 一提 |
| T1b | fork 核+分发 | `fi_r1/csrc/sparse_mla_sm120_prefill_fp4.cu`（复制 prefill.cu+dispatch_dsv4_dual 增 EXTRA 尺度格式模板参+pbs{128,256} 实例，§3.1/§3.7）；extra IO gather/尺度装载改 fp4 寻址；rope 两消费点接直解 | 设备端（探针窗内）首块对拍绿；案头=nvcc -c 编译过+PTX 含 e2m1x2 | T1b 一提 |
| T2 | fork python 壳 | `fi_r1/__init__.py`：JitSpec 名 `sparse_mla_sm120_fp4`（gen 同 jit/mla.py:35-49 式，源指向 fi_r1 目录）+仅 prefill 双缓存臂的薄分发（decode 臂不导入） | import+build_and_load 成功（无 GPU 环境编译期检查=compile-only 路径，若可用） | T2 一提 |
| T3 | 桥开关 | `kv_fp4.py`：`DSV41_FP4KV_R1_INKERNEL` 键+§3.8 路由（prefill 尺寸→fork 入口原样透传；关=现役路径零字节改动）+fail-safe 首块对拍+平台门 | 键关=现役形逐位（G5 构造性断言+横幅）；键开（无 GPU 桩）=路由单测 | T3 一提 |
| T4 | 测试件 | `fi_r1/t_r1_equiv.py`：§4.3 矩阵全案（host 位等+设备端 e2e torch.equal+fail-safe 四喂坏例必红） | 13/13 式全绿（A23-β 自检件先例 65eb3b5）；坏例红=断言生效证 | T4 一提 |
| T5 | 窗卡 | R1 探针装载窗卡（臂编成=47 键基座+R1 键臂 vs 基线臂成对；§五门全量预登记）另立 docs/taskcards/ | 窗卡评审位 | 另呈 |
- 红退线统一：R1 键关=47 键现役形（99e7ec92+overlay o12c1-prod）复原四查绿。
- 预期提交序列=T0→T1a→T1b→T2→T3→T4→T5（每任务一 commit，单文件 add；fi_r1 新目录逐文件 add）。

---

## 八、P1/R3 空位节（**10-11 已回填**：W-optD D0 臂实测〔窗事故收口版，census/P1_repack_overlap_D0.txt〕）
### 8.1 P1 repack 暴露量（法源：定谳件 §丙-2；W-optD D0 收窗相位 census V3.1 trace 维实测）
- **P1 实测（64k c8 深载窗 w3w0）=79.42 ms/step（931 calls，独流 tid=21）**；轻载窗 w3w1=0.33 ms/step；
  两窗混合=39.87 ms/step。**kernel-区间代数重叠=0.0%（与任何 GPU 事件零重叠=独流独占）**。
- **判读：落预测带 [29,81] 上侧⇒P1 带内成立；收益档位取高档（§1.4 表 [29,55,81] 三档≈+10.3% 侧）**。
- **口径差注记（在档争议面）**：定谳件「重叠率 ≥50.5% 强制成立」的重叠面=宽义（host 缝/异步发射间隙），
  trace 维 kernel-区间代数重叠=0% ⇒ repack 独流且不被 kernel 重叠——两口径差如实入档，**重叠账归因开放**
  （若宽义重叠成立则暴露量应低于核和 114.6ms；实测 79.4 独占恰介于其间，与「部分被 host 侧缝吸收」相容）。
- 64k/step↔128k/chunk 换算注记：D0 census 形=prefill@64k c8（非 128k 单流）——**已补（10-11
  seg_p128 专设探针，D0 形净靴，census/P1_repack_overlap_P128.txt）：@131072 c8 深载窗
  w3w1=120.902 ms/step（1368 calls，独流 tid=21，kernel-区间代数重叠 0.0%）**；轻载窗
  w3w0=0.328 ms/step。**出预测带 [29,81] 上界 49%（64k 79.42⇒128k 120.9=+52% 次线性）**；
  对同靴 census 步墙 453.52 ms/step 占比 **26.7%**（两窗 AGG gpu_busy 96.2%）。
- **128k 档判读（10-11 补）**：P1 实测出带上侧⇒原「带内成立/高档 +10.3%」判读上修——R1 整删
  repack 在 128k 档的暴露量基数=120.9 ms/step（步墙占比 26.7%），**R1 收益档位越原表
  [29,55,81] 三档上限**；G3 门（repack 族归零）预期值以 128k 档 120.9 基数同步记账。
  trace 维重叠 0% 两档（64k/128k）一致成立（与 §口径差注记相容性维持开放）。
- P0 census 复现门：**PASS**（D0 128k ttft 27.742s 落 27.7±0.3s）⇒ census 派生项免 ×0.948 标度；
  本卡 census 引数维持原值。37≠38 步分解悬置未解（无新证据）。
- G3 门（census repack 族归零核证）预期值对账：D0 基线 repack 族在 census JSON 计 1906.0ms/窗
  （w3w0）——R1 后该族应归零、注意力族不变，形状证锚点在档。

### 8.2 R3 topk 占用率（法源：定谳件 §2.1-R3；W1 前置 record-only 顺带）
- **R3 实测=未采集**（W-optD S5X 事故终止⇒D1/D2 prefill 相未跑，DSV41_FP4_BRIDGE_STATS 横幅
  无承载位；W-optD-2 顺带补或径直随 R1 整删消失）。
- 组合关系定谳（案头已结论，不受未采影响）：**R1 在 prefill 面吸收 R3**——R1 后无 gather 零行
  概念（核按 topk_length/索引掩蔽只消费真实行），零行填充面（kv_fp4_repack.py:197-199）随
  repack 整删消失；R3 独立价值仅剩 decode 面=0.53ms/step×(1−占用率)<0.53ms——**不值立项**
  （维持总卡弃路裁定；实测位永为记录位）。

---

## 附：外部锚点（T0 精读项来源；离线检索于本卡撰写日）
- flashinfer release highlights（2026-09）：DSV4 Flash sparse MLA NVFP4 KV on SM120/121
  （`kv_cache_format="nvfp4"`）；PR #4955 feat(sm120): add NVFP4 sparse MLA；PR #3640 SM120
  NVFP4 attention JIT 路径；已知问题 [sm120] NVFP4 KV: masked multi-token 性能异常（提示
  A' 路线须核verify masked/变长路径成熟度——我方 prefill 全程 topk_length 变长=同面）。
  来源：https://flashinfer.ai 、https://github.com/flashinfer-ai/flashinfer （issue/pr 页）。
- 定谳件所引「上游 FlashInfer #5197」离线未能索引（检索无此号）——以 #4955/#3640 为可锚替代，
  T0 亲核定案（§六-8）。
