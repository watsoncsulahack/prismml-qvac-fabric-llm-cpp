# Mali-G715 Bonsai Hardware Sweep

Date: 2026-06-13

## Summary

This benchmark is a hardware-profile sweep for `Ternary-Bonsai-1.7B-Q2_0.gguf` on the native Android/Termux Vulkan path. The goal was not to find a reasonable profile, but to identify the profile supported by quantitative evidence from the phone running the software.

Hardware path:

- GPU: Mali-G715
- Backend: Vulkan
- UMA/shared memory: enabled
- fp16: enabled
- int dot: enabled
- cooperative matrix support: `KHR_coopmat`
- reported free device memory: 15455 MiB

Headline:

- Full GPU offload, `-ngl 99`, was the correct placement for this Bonsai workload in the tested shapes.
- CPU-only decode improved with more threads up to `-t 6`, but still lost to full GPU offload.
- Partial offload, tested at `-ngl 1` and `-ngl 8`, was worse than both CPU-only and full GPU offload for decode.
- For full GPU offload, `-t 2` was the best thread setting in the short decode-focused sweep.
- In the prompt/batch sweep at `-ngl 99 -t 2`, `-b 512 -ub 64` had the fastest prompt processing and shortest wall-clock run. `-b 512 -ub 32` had the fastest decode row in that batch sweep.

## Runtime Proof

The benchmark was launched through native Termux with `com.termux.RUN_COMMAND`, not inside PRoot. The PRoot environment does not expose the real Vulkan device correctly.

Device discovery:

```text
ggml_vulkan: 0 = Mali-G715 (Mali-G715) | uma: 1 | fp16: 1 | bf16: 0 | warp size: 16 | shared memory: 32768 | int dot: 1 | matrix cores: KHR_coopmat
Available devices:
  Vulkan0: Mali-G715 (15455 MiB, 15455 MiB free)
```

Raw local artifacts:

```text
/data/data/com.termux/files/home/benchmarks/mali-bonsai-hardware-sweep-20260612T224200Z/
```

Sweep script:

```text
scripts/run_mali_bonsai_hardware_sweep.sh
```

## Command Shapes

The decode-focused sweep used:

```sh
llama-bench \
  -m /data/data/com.termux/files/home/Ternary-Bonsai-1.7B-Q2_0.gguf \
  -p 64 \
  -n 64 \
  -r 1 \
  -b 256 \
  -ub 64 \
  -fa 0 \
  --no-warmup \
  -o json
```

The batch/microbatch sweep used:

```sh
llama-bench \
  -m /data/data/com.termux/files/home/Ternary-Bonsai-1.7B-Q2_0.gguf \
  -dev Vulkan0 \
  -ngl 99 \
  -t 2 \
  -p 512 \
  -n 32 \
  -r 1 \
  -fa 0 \
  --no-warmup \
  -o json
```

## Result Columns

The chart columns should keep size context visible:

- `Prompt tokens`: `llama-bench -p`; synthetic prompt token count for benchmark rows.
- `Gen tokens`: `llama-bench -n`; generated token count.
- `Total tokens`: prompt plus generated tokens for a quick row-size comparison.
- `Prompt chars`: source prompt character count when testing a real prompt; `0` means the row used synthetic `llama-bench -p` tokens.
- `Model token bytes`: per-token model-side byte size being annotated for the run, such as KV bytes per token, when known; `0` means not annotated.

## Decode and Placement Results

Rows are `llama-bench` prompt-processing throughput (`PP tok/s`) and token-generation throughput (`TG tok/s`). Higher is better.

### CPU-only baseline

Command shape: `-dev none -ngl 0 -b 256 -ub 64 -fa 0 -p 64 -n 64 -r 1`.

| Threads | PP tok/s | TG tok/s | Wall time |
| ---: | ---: | ---: | ---: |
| 1 | 2.86 | 2.59 | 179s |
| 2 | 4.94 | 3.17 | 167s |
| 4 | 5.36 | 4.13 | 175s |
| 6 | 8.02 | 5.45 | 71s |
| 8 | invalid | invalid | killed after 845s |

Finding:

CPU-only decode scales up to `-t 6` in this short test, but it never reaches the full-GPU decode throughput. `-t 8` was not a usable CPU-only profile in this run.

### Partial GPU offload

Command shape: `-dev Vulkan0 -b 256 -ub 64 -fa 0 -p 64 -n 64 -r 1`.

| GPU layers | Threads | PP tok/s | TG tok/s | Wall time |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 5.10 | 1.38 | 305s |
| 1 | 2 | 4.99 | 2.27 | 196s |
| 1 | 4 | 4.92 | 1.58 | partial run |
| 8 | 1 | 4.35 | 1.62 | 314s |
| 8 | 2 | 3.76 | 2.20 | 237s |

Finding:

Partial offload is not the right split for this workload. The model still has to execute layer-by-layer, and the CPU/GPU synchronization cost dominates any benefit from placing only a few layers on Vulkan.

### Full GPU offload

Command shape: `-dev Vulkan0 -ngl 99 -b 256 -ub 64 -fa 0 -p 64 -n 64 -r 1`.

| Threads | PP tok/s | TG tok/s | Wall time |
| ---: | ---: | ---: | ---: |
| 1 | 5.65 | 8.67 | 110s |
| 2 | 10.64 | 9.84 | 44s |
| 4 | 7.40 | 8.94 | 102s |
| 6 | 5.46 | 7.53 | 93s |
| 8 | 6.76 | 9.29 | 78s |

Finding:

`-ngl 99 -t 2` is the best row in this decode-focused sweep. It beats the best CPU-only decode row by about 81% (`9.84` vs `5.45` TG tok/s), and has the best wall-clock time.

## Batch and Microbatch Results

Command shape: `-dev Vulkan0 -ngl 99 -t 2 -fa 0 -p 512 -n 32 -r 1`.

| Batch | Microbatch | Prompt tokens | Gen tokens | Total tokens | Prompt chars | Model token bytes | PP tok/s | TG tok/s | Wall time |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 32 | 512 | 32 | 544 | 0 | 114688 | 13.26 | 9.71 | 171s |
| 64 | 64 | 512 | 32 | 544 | 0 | 114688 | 19.05 | 6.85 | 191s |
| 128 | 32 | 512 | 32 | 544 | 0 | 114688 | 12.70 | 6.57 | 240s |
| 128 | 64 | 512 | 32 | 544 | 0 | 114688 | 21.70 | 7.33 | 173s |
| 128 | 128 | 512 | 32 | 544 | 0 | 114688 | 7.47 | 7.18 | 291s |
| 256 | 32 | 512 | 32 | 544 | 0 | 114688 | 14.19 | 8.67 | 159s |
| 256 | 64 | 512 | 32 | 544 | 0 | 114688 | 18.21 | 8.58 | 188s |
| 256 | 128 | 512 | 32 | 544 | 0 | 114688 | 7.57 | 6.61 | 263s |
| 512 | 32 | 512 | 32 | 544 | 0 | 114688 | 13.53 | 11.02 | 166s |
| 512 | 64 | 512 | 32 | 544 | 0 | 114688 | 23.52 | 7.38 | 141s |
| 512 | 128 | 512 | 32 | 544 | 0 | 114688 | 7.37 | 7.27 | 378s |

Finding:

`-b 512 -ub 64` is the strongest prompt-processing row and the fastest overall row in this phase. `-b 512 -ub 32` is the strongest decode row, but has much slower prompt processing than `-b 512 -ub 64`.

`-ub 128` is consistently poor on this phone-class Vulkan path. It should not be the default microbatch for Bonsai.

## Confirmation Sweep Results

Date: 2026-06-14

Command shape: `-dev Vulkan0 -ngl 99 -t 2 -fa 0 -p 512 -n 32 -r 3`.

Raw local artifacts:

```text
/data/data/com.termux/files/home/benchmarks/mali-bonsai-hardware-sweep-20260614T050159Z/
```

| Batch | Microbatch | Prompt tokens | Gen tokens | Total tokens | Prompt chars | Model token bytes | PP tok/s | TG tok/s | Wall time |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128 | 32 | 512 | 32 | 544 | 0 | 114688 | 22.17 | 16.07 | 77s |
| 128 | 64 | 512 | 32 | 544 | 0 | 114688 | 43.60 | 16.18 | 43s |
| 256 | 32 | 512 | 32 | 544 | 0 | 114688 | 22.23 | 16.08 | 77s |
| 256 | 64 | 512 | 32 | 544 | 0 | 114688 | 43.15 | 16.00 | 44s |

Finding:

In this repeated confirmation sweep, `-ub 64` is the better microbatch shape for this prompt-heavy row. Both `128/64` and `256/64` roughly doubled prompt-processing throughput versus `-ub 32`, while token-generation throughput stayed effectively tied around 16 tok/s. `128/64` has the best wall-clock time by a narrow margin, and `256/64` is close enough that either is defensible; keep `256/64` as the conservative continuity setting unless later server TTFT rows prefer `128/64`.

## Current Evidence-backed Profile

For Bonsai 1.7B Q2_0 on this Mali-G715 path, the stable parts of the measured profile are:

```sh
-ngl 99 -t 2 -fa 0 -ub 64
```

For broad synthetic prompt processing, `-b 512 -ub 64` remains the strongest row from the earlier sweep. For the confirmation subset, `-b 128 -ub 64` and `-b 256 -ub 64` are effectively tied, with `128/64` slightly ahead on wall-clock.

For `llama-server`, keep prompt-cache behavior separate from hardware throughput testing. The earlier server behavior showed `--cache-ram 0` giving more consistent repeated short requests, so server-level validation should test both:

```sh
# cold-prompt / benchmark profile
-c 4096 -np 1 -ngl 99 -t 2 --flash-attn off -b 512 -ub 64 --cache-ram 0

# repeated-prefix UX profile
-c 4096 -np 1 -ngl 99 -t 2 --flash-attn off -b 512 -ub 64
```

## Interpretation

The CPU is not the better decode device for Bonsai in this measured setup. CPU-only decode can be made less bad with thread tuning, but full GPU offload is better for both prefill and decode in the tested prompt/generation shapes.

The correct delegation model for this project is therefore not "GPU for prefill, CPU for decode." It is:

- GPU handles all model layers: `-ngl 99`
- CPU thread count stays low enough to avoid oversubscription: currently `-t 2`
- batch/microbatch tune the Vulkan work shape: currently `-b 512 -ub 64`
- prompt-cache behavior is measured separately at the server/agent layer

## Caveats

- The original broad sweep used one repetition and no warmup.
- The 2026-06-14 confirmation sweep used three repetitions, but still no warmup.
- Rows were run sequentially, so thermal state may influence later rows.
- `llama-bench` isolates model throughput; it does not include HTTP server overhead, prompt-cache behavior, slot reuse, or Pi agent tool-loop behavior.
- This benchmark covers Bonsai 1.7B Q2_0 only. Gemma or larger models may have a different optimum.

## Next Step

Move to `llama-server` TTFT testing with the Pi agent prompt shape, and compare the ubatch-64 candidates in the actual server path:

```sh
-b 128 -ub 64
-b 256 -ub 64
-b 512 -ub 64
```

Also measure cache behavior separately. Android/Termux did not expose the usual Linux CPU cache metadata in this run, so use a fallback ladder:

```sh
# CPU cache metadata, if the kernel exposes it
for d in /sys/devices/system/cpu/cpu0/cache/index*; do
  echo "$d"
  for f in level type size coherency_line_size ways_of_associativity number_of_sets; do
    [ -r "$d/$f" ] && printf '  %s=' "$f" && cat "$d/$f"
  done
done

# Device-tree cache hints, if readable
find /proc/device-tree -iname '*cache*' -o -iname '*l2*' 2>/dev/null

# Vulkan-visible limits; this usually will not reveal L2 size directly
vulkaninfo 2>/dev/null | grep -iE 'cache|memory|subgroup|timestamp|shared'
```

If those paths stay blank, use an empirical cache-size probe: run a small GPU or CPU memory-access microbenchmark across buffer sizes from 128 KiB to 8 MiB and look for the bandwidth/latency knee. That will not name the vendor's exact L2 configuration, but it gives the working-set limit that matters for batch/microbatch tuning.
