# KV Cache and Flash Attention Benchmark on Mali-G715

Date: 2026-06-11

## Summary

This pass compared flash attention and KV-cache precision for:

- `Ternary-Bonsai-1.7B-Q2_0.gguf`
- `gemma-4-E2B-it-Q4_K_M.gguf`

Hardware path:

- GPU: Mali-G715
- Vulkan backend: enabled
- UMA/shared memory: enabled
- fp16: enabled
- int dot: enabled
- cooperative matrix support: `KHR_coopmat`
- reported free device memory: 15455 MiB

For this short and medium prompt benchmark, the fastest setting for both models was:

```sh
-fa 0 -ctk f16 -ctv f16
```

Flash attention did not improve throughput at 512 or 2048 prompt tokens. KV-cache quantization reduced memory footprint in principle, but slowed generation and did not improve prompt processing in this test shape.

## Command Shape

Each profile used:

```sh
llama-bench \
  -p 512,2048 \
  -n 32 \
  -b 256 \
  -ub 64 \
  -ngl 99 \
  -r 1 \
  --no-warmup \
  -o json
```

Profiles:

- `f16-fa0`: `-fa 0 -ctk f16 -ctv f16`
- `f16-fa1`: `-fa 1 -ctk f16 -ctv f16`
- `q8-fa1`: `-fa 1 -ctk q8_0 -ctv q8_0`
- `q4-fa1`: `-fa 1 -ctk q4_0 -ctv q4_0`

Raw local artifacts:

```text
/root/.openclaw/workspace/benchmarks/kv-flash-attn-2026-06-11-fast/
```

## Results

### Bonsai 1.7B Q2_0

| Profile | PP 512 tok/s | PP 512 time | PP 2048 tok/s | PP 2048 time | TG 32 tok/s | TG 32 time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| f16-fa0 | 30.10 | 17.0s | 37.78 | 54.2s | 10.60 | 3.0s |
| f16-fa1 | 29.69 | 17.2s | 35.70 | 57.4s | 9.81 | 3.3s |
| q8-fa1 | 28.79 | 17.8s | 34.04 | 60.2s | 6.47 | 4.9s |
| q4-fa1 | 28.02 | 18.3s | 34.46 | 59.4s | 7.86 | 4.1s |

Finding:

`f16-fa0` is best for the tested prompt sizes. Flash attention slowed prompt processing slightly and reduced decode speed. KV q8/q4 did not help for this context length.

### Gemma 4 E2B Q4_K_M

| Profile | PP 512 tok/s | PP 512 time | PP 2048 tok/s | PP 2048 time | TG 32 tok/s | TG 32 time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| f16-fa0 | 20.45 | 25.0s | 30.17 | 67.9s | 5.19 | 6.2s |
| f16-fa1 | 20.00 | 25.6s | 26.05 | 78.6s | 5.18 | 6.2s |
| q8-fa1 | 20.42 | 25.1s | 24.52 | 83.5s | 4.58 | 7.0s |
| q4-fa1 | 20.18 | 25.4s | 25.28 | 81.0s | 4.11 | 7.8s |

Finding:

`f16-fa0` is also best for Gemma 4 E2B at 512 and 2048 prompt tokens. Flash attention hurt 2048-token prompt processing, and q8/q4 KV reduced generation throughput.

## Recommendation

Use this as the default interactive profile for both Bonsai 1.7B and Gemma 4 E2B on this Mali-G715 device:

```sh
-c 4096 -np 1 -ngl 99 -fa 0 -b 256 -ub 64 --cache-ram 0
```

Do not enable flash attention or KV-cache quantization by default for short/medium Pi interactions.

Continue testing KV q8/q4 only for longer-context profiles, where memory pressure may matter more than raw short-prompt throughput. The next useful pass is:

```sh
-c 8192  -fa 0 -ctk f16  -ctv f16
-c 8192  -fa 1 -ctk q8_0 -ctv q8_0
-c 8192  -fa 1 -ctk q4_0 -ctv q4_0
-c 16384 -fa 1 -ctk q8_0 -ctv q8_0
-c 16384 -fa 1 -ctk q4_0 -ctv q4_0
```

Those should be measured with server-level TTFT and phone responsiveness, not only `llama-bench`, because longer contexts are where shared-memory pressure and Android UI responsiveness become the deciding factors.

## Caveats

- This was a fast benchmark pass: one repetition, no warmup.
- Results are strong enough for launch-profile selection, but not final enough for publication-grade statistics.
- `llama-bench` isolates prompt and generation rates. It does not fully represent Pi agent latency, HTTP server behavior, prompt-cache behavior, or UI responsiveness.
- The q8/q4 profiles may still win at larger contexts if f16 KV causes memory pressure or swap.
