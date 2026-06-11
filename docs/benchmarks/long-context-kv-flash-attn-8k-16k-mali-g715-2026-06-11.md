# Long-Context KV and Flash Attention Benchmark on Mali-G715

Date: 2026-06-11

## Summary

This follow-up extends the Mali-G715 KV-cache and flash-attention benchmark from short/medium prompts to 8k and a narrow 16k viability probe.

Models:

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

Headline:

- 8k context is measurable but slow. It is a long-context mode, not a normal low-latency chat mode.
- For 8k, the fastest profile remained `-fa 0 -ctk f16 -ctv f16` for both Bonsai 1.7B and Gemma 4 E2B.
- Flash attention and KV q8/q4 did not improve throughput at 8k in this benchmark shape.
- 16k did not produce usable benchmark rows before manual stop. Treat 16k+ as a server-level viability experiment, not an interactive default.

## Command Shape

The 8k pass used:

```sh
llama-bench \
  -p 8192 \
  -n 16 \
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

The 16k narrow probe used:

```sh
llama-bench \
  -p 16384 \
  -n 8 \
  -b 256 \
  -ub 64 \
  -ngl 99 \
  -r 1 \
  --no-warmup \
  -o json
```

Profiles selected for 16k:

- `f16-fa0`: speed baseline
- `q4-fa1`: memory-saving extreme

Raw local artifacts:

```text
/root/.openclaw/workspace/benchmarks/kv-flash-attn-8k-16k-2026-06-11/
```

## 8k Results

### Bonsai 1.7B Q2_0

| Profile | PP 8192 tok/s | PP 8192 time | TG 16 tok/s | TG 16 time |
| --- | ---: | ---: | ---: | ---: |
| f16-fa0 | 29.38 | 278.8s | 10.18 | 1.6s |
| f16-fa1 | 24.36 | 336.3s | 9.27 | 1.7s |
| q8-fa1 | 25.24 | 324.5s | 4.71 | 3.4s |
| q4-fa1 | 25.94 | 315.8s | 5.24 | 3.1s |

Finding:

`f16-fa0` remained best. The q8/q4 profiles reduced memory pressure during the run, but at the cost of slower prompt processing and much slower decode. At 8k, compressed KV is a memory-headroom option, not a speed option.

### Gemma 4 E2B Q4_K_M

| Profile | PP 8192 tok/s | PP 8192 time | TG 16 tok/s | TG 16 time |
| --- | ---: | ---: | ---: | ---: |
| f16-fa0 | 27.21 | 301.0s | 4.95 | 3.2s |
| f16-fa1 | 17.24 | 475.1s | 2.09 | 7.7s |
| q8-fa1 | 16.37 | 500.3s | 3.89 | 4.1s |
| q4-fa1 | 20.85 | 392.9s | 3.99 | 4.0s |

Finding:

`f16-fa0` was again fastest. Flash attention hurt Gemma 4 E2B significantly at 8k. q4 was better than q8 for prompt processing, but still slower than the f16/fa-off baseline.

## 16k Viability Probe

The 16k pass was intentionally narrow. It did not produce successful JSON rows.

Observed progress:

| Model | Profile | Outcome |
| --- | --- | --- |
| Bonsai 1.7B | f16-fa0 | manually stopped after ~47m without final JSON |
| Bonsai 1.7B | q4-fa1 | interrupted during cleanup; no valid row |
| Gemma 4 E2B | f16-fa0 | manually stopped; no valid row |
| Gemma 4 E2B | q4-fa1 | manually stopped; no valid row |

This should be interpreted conservatively: the 16k `llama-bench` shape was not practical enough to complete cleanly during the run. It does not prove 16k is impossible, but it does mean 16k should not be treated as a reasonable default for this phone-class setup.

## Recommendation

For normal Pi use, keep:

```sh
-c 4096 -np 1 -ngl 99 -fa 0 -b 256 -ub 64 --cache-ram 0
```

For occasional long-context use, 8k is the current practical upper test target:

```sh
-c 8192 -np 1 -ngl 99 -fa 0 -b 256 -ub 64 --cache-ram 0
```

Do not enable flash attention by default on this Mali-G715 path for Bonsai 1.7B or Gemma 4 E2B.

Do not use q8 KV as the default long-context setting based on these results. It was slower than f16/fa-off for both models and especially poor for Gemma 4 E2B at 8k.

Use q4 KV only as a fallback when memory pressure or swap becomes the limiting factor:

```sh
-c 8192 -np 1 -ngl 99 -fa 1 -ctk q4_0 -ctv q4_0 -b 256 -ub 64 --cache-ram 0
```

That q4 profile is a survival profile, not a speed profile.

## Next Step

The next benchmark should move from `llama-bench` to server-level testing:

- launch `llama-server` with the recommended 4k and 8k profiles
- measure TTFT and total time through the OpenAI-compatible HTTP API
- include prompt-cache disabled with `--cache-ram 0`
- collect RSS/swap and Android responsiveness observations
- test one real Pi agent prompt, not just synthetic prompt/generation rates

This matters because 8k prompt processing is already multi-minute in `llama-bench`, and the user experience depends more on TTFT and phone responsiveness than on isolated throughput alone.

## Caveats

- One repetition, no warmup.
- `llama-bench` isolates prompt processing and decode; it does not fully represent Pi agent latency or HTTP server behavior.
- The 16k probe was interrupted manually after it failed to produce useful rows in a practical amount of time.
- Longer context may still work for offline batch use, but it is not currently a good interactive target on this device.
