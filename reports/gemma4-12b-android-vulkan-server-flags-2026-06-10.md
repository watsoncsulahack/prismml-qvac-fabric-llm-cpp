# Gemma 4 12B Android Vulkan Server Flag Benchmark

Date: 2026-06-10 UTC

## Summary

This report compares llama-server launch flags for Gemma 4 12B IT Q4 on an
Android ARM64 Vulkan runtime. The goal was to improve interactive
responsiveness, especially the delay before the first streamed token.

The clearest finding is that prompt caching should be disabled for this setup:
`--cache-ram 0` removed a large prompt-cache update stall and made repeated
short requests consistent.

## Runtime

```text
GPU: Mali-G715
Backend: Vulkan0
Binary: Android ARM64 Vulkan llama.cpp build
Model: gemma-4-12b-it-qat-q4_0.gguf
```

## llama-bench Baseline

Command shape:

```sh
LD_LIBRARY_PATH="$PWD" ./llama-bench \
  -m /path/to/gemma-4-12b-it-qat-q4_0.gguf \
  -r 1 -p 128 -n 32 -ngl 99 -fa 0 -b 256 -ub 64 -o md
```

Result:

| Test | Throughput |
| --- | ---: |
| Prompt processing, `pp128` | 5.98 tok/s |
| Token generation, `tg32` | 2.13 tok/s |

Larger batch settings such as `-b 512 -ub 128` caused high memory pressure and
did not produce a useful measurement in this run.

## Server Flag Comparison

Each server test used one slot, `-c 4096`, `-ngl 99`, `-b 256`, `-ub 64`, and
a short streaming chat completion. Time to first token is approximated with
curl's `time_starttransfer`.

| Launch variant | TTFT | Total time | Prompt eval | Decode | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| `-fa off` | 12.09 s | 27.28 s | 1.91 tok/s | 2.11 tok/s | stable |
| `-fa on` | 12.76 s | 27.76 s | 1.81 tok/s | 2.13 tok/s | stable |
| `-fa on -ctk q4_0 -ctv q4_0` | 13.38 s | 29.79 s | 1.73 tok/s | 1.95 tok/s | stable, lower KV memory |
| `-fa off -ctk q4_0 -ctv q4_0` | n/a | n/a | n/a | n/a | invalid; V cache q4 requires flash attention |
| default prompt cache, request 1 | 11.98 s | 27.01 s | 1.93 tok/s | 2.13 tok/s | stable |
| default prompt cache, request 2 | 151.35 s | 166.18 s | 2.07 tok/s | 2.16 tok/s | prompt-cache update stall |
| `--cache-ram 0`, request 1 | 12.17 s | 27.18 s | 1.90 tok/s | 2.13 tok/s | stable |
| `--cache-ram 0`, request 2 | 11.19 s | 25.88 s | 2.06 tok/s | 2.18 tok/s | stable |

## Recommended Interactive Launch

```sh
cd /path/to/android-arm64-vulkan
LD_LIBRARY_PATH="$PWD" ./llama-server \
  -m /path/to/gemma-4-12b-it-qat-q4_0.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -c 4096 \
  -np 1 \
  -ngl 99 \
  -fa off \
  -b 256 \
  -ub 64 \
  --cache-ram 0 \
  --metrics \
  --log-file /path/to/llama-server-12b.log \
  --log-timestamps
```

For larger-context tests, `-fa on -ctk q4_0 -ctv q4_0` is worth testing because
it substantially reduces KV-cache memory. In this short-prompt benchmark, it
was slower than the f16 KV-cache baseline.
