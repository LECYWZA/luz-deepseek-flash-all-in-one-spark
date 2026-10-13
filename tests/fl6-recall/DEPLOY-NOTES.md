# FL6 修复部署件（dev/fl6-recall/）

## 文件清单

- `fl6_recall.py` — 生产 adapter 组件（部署到 `~/migrate-assets/dsv41/adapter/`）
- `fl6_fix.py` — 案头 monkey-patch（同源逻辑，测试用，不部署）
- `test_fl6_swa_recall.py` — 双臂 6 测（部署前后均可回归）
- `DEPLOY-NOTES.md` — 本件

## 部署步骤（验证窗内执行，呈裁后）

1. **入位**：`fl6_recall.py` 复制到 `~/migrate-assets/dsv41/adapter/fl6_recall.py`（四机共享路径，在位核验）。
2. **接线**：`sitecustomize.py` 的 `EngramLoader.exec_module` elif 链追加两行分支（建议位置：`sglang.srt.managers.scheduler` 分支之前）：

```python
        elif module.__name__ == 'sglang.srt.mem_cache.unified_cache.unified_tree_core':
            # FL6 recall fix (QA31 cp30 0/3): SWA interior retirement + match
            # retract. Dormant unless DSV41_FL6_RECALL_FIX is set; raises on
            # 79cafec0 symbol drift.
            from fl6_recall import install as install_fl6_recall
            install_fl6_recall(module)
        elif module.__name__ == 'sglang.srt.mem_cache.unified_cache.components.swa':
            from fl6_recall import install_swa as install_fl6_recall_swa
            install_fl6_recall_swa(module)
```

3. **指纹**：sitecustomize.py 变更后重算 adapter 指纹（原 2c4baad3 → 新值），窗内 adapter-sync `--expect` 更新为新值。
4. **门控**：boot 环境加 `DSV41_FL6_RECALL_FIX=1`（未设=休眠=原版行为逐字，回退零成本）。
5. **生效直证**：容器日志 grep `'[fl6_recall]'` — 应见两行：
   `[fl6_recall] tree_core patched (mode=both)` / `[fl6_recall] swa patched (mode=both, retire=True, retract=True)`。缺行=门控休眠或漂移拒起（fail-closed）。

## 门控语义（DSV41_FL6_RECALL_FIX）

| 取值 | 行为 |
|---|---|
| 未设 / 0 / off / false | 休眠：零 patch，原版逐字 |
| 1 / on / true | B1+A 双修（转正候选形态） |
| retire | 仅 B1（判别臂：FL6 门必要充分修复） |
| retract | 仅 A（判别臂：兜底层） |

## 案头回归（部署前/后均可跑）

```
FL6_USE_ADAPTER=1 DSV41_FL6_RECALL_FIX=1 \
  PYTHONPATH=/tmp/fl6stubs:/home/liux***ya/sglang-main-src/python:. \
  /tmp/fl6venv/bin/python test_fl6_swa_recall.py      # 修复臂 6/6 绿
FL6_APPLY_FIX=0 ... 同上                               # 对照臂：test_10 复现 bug
```

（环境件若失效重建：venv --system-site-packages + orjson/pybase64/starlette/msgspec/zmq/tqdm/IPython/pydantic/transformers/torchvision/dill/sentencepiece/compressed_tensors/openai/partial_json_parser + /tmp/fl6stubs/sitecustomize.py 桩 flashinfer/sgl_kernel/gguf）
