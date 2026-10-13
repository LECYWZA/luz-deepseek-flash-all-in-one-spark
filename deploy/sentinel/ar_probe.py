import os, time, statistics, torch
import torch.distributed as dist

rank = int(os.environ["RANK"])
world = int(os.environ.get("WORLD_SIZE", "4"))
sz_bytes = int(os.environ.get("AR_PROBE_BYTES", "33554432"))  # 32MB default
iters = int(os.environ.get("AR_PROBE_ITERS", "20"))
warmup = int(os.environ.get("AR_PROBE_WARMUP", "5"))

torch.cuda.set_device(0)
dist.init_process_group("nccl", init_method="env://", world_size=world, timeout=__import__('datetime').timedelta(seconds=180))
t = torch.ones(sz_bytes // 4, dtype=torch.float32, device="cuda")  # 32MB fp32

for _ in range(warmup):
    dist.all_reduce(t)
torch.cuda.synchronize()
times = []
for _ in range(iters):
    torch.cuda.synchronize(); t0 = time.perf_counter()
    dist.all_reduce(t)
    torch.cuda.synchronize(); times.append((time.perf_counter() - t0) * 1e6)

if rank == 0:
    print(f"AR_PROBE_BYTES {sz_bytes}")
    print(f"AR32M_US_MEDIAN {statistics.median(times):.1f}")
    print(f"AR32M_US_AVG {statistics.mean(times):.1f}")
    print(f"AR32M_US_MIN {min(times):.1f}")
    print(f"AR32M_US_MAX {max(times):.1f}")
dist.barrier()
dist.destroy_process_group()
