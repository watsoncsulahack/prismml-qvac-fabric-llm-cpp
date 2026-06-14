# Mali-G715 Gemma 4 E2B Q4_K_M Batch Sweep

Date: 2026-06-14

## Summary

This benchmark measures the same batch/microbatch sweep that improved the
interactive Pi session, but on `gemma-4-E2B-it-Q4_K_M.gguf` instead of the
Ternary-Bonsai 1.7B model.

The qualitative interactive result matches the quantitative result: `-ub 64`
is the important change, and `-b 512 -ub 64` is the strongest row measured so
far in this Gemma 4 E2B sweep.

## Runtime Proof

Hardware path:

- Device: Pixel 9 Pro Fold / Tensor G4
- GPU: Mali-G715
- Backend: Vulkan
- Vulkan device: `Vulkan0`
- UMA/shared memory: enabled
- fp16: enabled
- int dot: enabled
- cooperative matrix support: `KHR_coopmat`

Model:

```text
/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf
```

`llama-bench` reported:

```text
model_type: gemma4 E2B Q4_K - Medium
model_size: 3090917516 bytes
model_n_params: 4647450147
type_k/type_v: f16/f16
flash_attn: false
```

Metadata used for the model-token-size annotation:

```text
gemma4.block_count = 35
gemma4.attention.head_count_kv = 1
gemma4.attention.key_length = 512
gemma4.attention.value_length = 512
```

With f16 KV, the simple per-token KV annotation is:

```text
(1 * 512 key + 1 * 512 value) * 2 bytes * 35 layers = 71680 bytes/token
```

Raw local artifacts:

```text
/data/data/com.termux/files/home/benchmarks/mali-gemma4-e2b-q4km-hardware-sweep-20260614T072048Z/
/data/data/com.termux/files/home/benchmarks/mali-gemma4-e2b-q4km-hardware-sweep-512-20260614T074717Z/
/data/data/com.termux/files/home/benchmarks/mali-gemma4-e2b-q4km-targeted-20260614T075314Z/
```

## Command Shape

The sweep used:

```sh
MODEL=/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf \
BATCH_UBATCH_SWEEP="128:32 128:64 256:32 256:64" \
PROMPT_TOKENS=512 \
GEN_TOKENS=32 \
REPEAT=3 \
SWEEP_THREADS=2 \
SWEEP_NGL=99 \
FLASH_ATTN=0 \
MODEL_TOKEN_BYTES=71680 \
scripts/run_mali_bonsai_hardware_sweep.sh
```

Equivalent `llama-bench` shape:

```sh
llama-bench \
  -m /data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf \
  -dev Vulkan0 \
  -ngl 99 \
  -t 2 \
  -p 512 \
  -n 32 \
  -r 3 \
  -fa 0 \
  --no-warmup \
  -o json
```

## Results

Rows are prompt-processing throughput (`PP tok/s`) and token-generation
throughput (`TG tok/s`). Higher is better.

| Batch | Microbatch | Prompt tokens | Gen tokens | Total tokens | Prompt chars | Model token bytes | PP tok/s | TG tok/s | Wall time |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128 | 32 | 512 | 32 | 544 | 0 | 71680 | 9.18 | 3.93 | 204s |
| 128 | 64 | 512 | 32 | 544 | 0 | 71680 | 31.03 | 3.97 | 84s |
| 256 | 32 | 512 | 32 | 544 | 0 | 71680 | 11.68 | 4.15 | 168s |
| 256 | 64 | 512 | 32 | 544 | 0 | 71680 | 31.36 | 7.34 | 71s |
| 512 | 64 | 512 | 32 | 544 | 0 | 71680 | 32.41 | 7.93 | 65s |
| 512 | 128 | 512 | 32 | 544 | 0 | 71680 | 8.24 | 6.51 | 206s |

## Finding

`-ub 64` is clearly better than `-ub 32` for Gemma 4 E2B on this Mali-G715
Vulkan path. `-ub 128` regresses badly even with `-b 512`, so the original
large microbatch shape should not be used for the interactive profile.

The best row is:

```sh
-ngl 99 -t 2 -fa 0 -b 512 -ub 64
```

Compared with `128/32`, `512/64` is about 3.5x faster in prompt processing
(`32.41` vs `9.18` PP tok/s), about 2.0x faster in token generation (`7.93` vs
`3.93` TG tok/s), and about 3.1x faster wall-clock (`65s` vs `204s`).

Compared with `256/64`, `512/64` is modestly better in prompt processing,
decode throughput, and wall-clock. That makes `512/64` the better default for
the interactive Pi session with Gemma 4 E2B.

## Targeted Follow-Up

After `512/64` became the best batch/microbatch row, a small follow-up tested
thread count, flash attention, and q4 KV against the same shape:

| Label | Threads | Flash attn | KV type | PP tok/s | TG tok/s | Wall time | Result |
| --- | ---: | --- | --- | ---: | ---: | ---: | --- |
| `t1-fa0` | 1 | off | f16/f16 | 30.16 | 6.97 | 73s | slower than baseline |
| `t2-fa0` | 2 | off | f16/f16 | 32.41 | 7.93 | 65s | best measured row |
| `t4-fa0` | 4 | off | f16/f16 | 30.52 | 6.34 | 73s | slower than baseline |
| `t2-fa1` | 2 | on | f16/f16 | 29.09 | 6.81 | 76s | slower than baseline |
| `t2-fa0-kvq4` | 2 | off | q4/q4 | invalid | invalid | 7s | failed to create context |

For this model and device, the next measured speed profile should keep
`-t 2`, `--flash-attn off`, and f16 KV.

## QVAC/Fabric Fork Assessment

The local `qvac-fabric-llm.cpp` checkout is based on an older upstream baseline
and reports as far behind the current PrismML/llama.cpp worktree. The available
QVAC Android server binaries also report `int dot: 0` on this Mali-G715 device,
where the current PrismML Android Vulkan artifact reports `int dot: 1`.

QVAC/Fabric still has ideas worth tracking:

- a runtime tuning script that sweeps batch, microbatch, context, threads,
  flash attention, and memory flags;
- BitNet/TQ2_0 support and training paths;
- memory-based model loading;
- mobile GPU work, especially Adreno-oriented Vulkan work and VMA integration.

For Gemma 4 E2B speed on this Pixel/Mali path, none of those are a better
immediate path than the current PrismML/llama.cpp line. The current tree already
has Gemma 4 support, Gemma 4 tool-call parsing, `cache-ram`, unified KV,
CPU-MoE flags, fit-target flags, and Vulkan op coverage. Treat QVAC as a source
of tuning ideas or possible later ports, not as the main runtime for this Gemma
profile until it is rebased and shown to run this model with equal or better
Vulkan feature detection.

## Recommended Interactive Server Profile

Use this as the next qualitative `llama-server` profile:

```sh
cd /data/data/com.termux/files/home

export LD_LIBRARY_PATH=/data/data/com.termux/files/home/android-arm64-vulkan${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

./android-arm64-vulkan/llama-server \
  -m /data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -dev Vulkan0 \
  -ngl 99 \
  -t 2 \
  -tb 2 \
  -c 4096 \
  -np 1 \
  -b 512 \
  -ub 64 \
  --flash-attn off \
  --metrics \
  --slots
```

For cold-prompt TTFT discipline, add `--cache-ram 0`. For interactive Pi use,
leave cache behavior at the default so repeated-prefix behavior can help.

## Notes

- The `prompt_chars` column is `0` because this was a synthetic `llama-bench`
  token-count benchmark, not a real prompt-text benchmark.
- The sweep was sequential and used no warmup, so thermal state may still
  influence later rows.
- The Ternary-Bonsai `128/64` and `256/64` result should not be reused for
  Gemma. In this Gemma run, `512/64` is materially better.
