# Mali-G715 Gemma Agent Next Phase

Date: 2026-06-15

This is the follow-up plan after the first raw grouped sweep in
`mali-g715-gemma-agent-raw-sweep-2026-06-14.md`.

The goal is to tighten the profile around the primary Gemma 4 E2B
`UD-Q4_K_XL` model, then compare it against the Gemma `Q4_K_M` candidate and
the Ternary-Bonsai size ladder before spending more time on longer
server-session tests.

## Current Baseline

Primary model:

```text
/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
```

Known-good conservative server profile:

```text
-dev Vulkan0 -ngl 99 -t 2 -tb 2 -fa 0 -c 4096 -b 512 -ub 64 -ctk f16 -ctv f16
```

Best raw prompt-ingestion candidate:

```text
-dev Vulkan0 -ngl 99 -t 2 -tb 2 -fa 0 -c 4096 -b 768 -ub 64 -ctk f16 -ctv f16
```

The first raw sweep found:

- `768/64` gave most of the prompt-processing gain.
- `1024/64` did not meaningfully improve prompt processing over `768/64`.
- `ub=80` and `ub=96` badly hurt prompt processing.
- `4096` context remains the practical default.
- `8192` context is viable but slower.

## Model Set

The LFM2 8B A1B model is intentionally out of this round. It should be tested
later as a separate MoE comparison.

| Label | Family | Size class | Quant | Approx file size | Path | Status |
| --- | --- | ---: | --- | ---: | --- | --- |
| `primary_xl` | Gemma 4 E2B | 4.6B params | `UD-Q4_K_XL` | ~2.6 GB | `/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf` | primary |
| `q4km` | Gemma 4 E2B | 4.6B params | `Q4_K_M` | pending | `/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf` | comparison |
| `bonsai1p7b` | Ternary-Bonsai | 1.7B params | `Q2_0` | pending | `/data/data/com.termux/files/home/models/Ternary-Bonsai-1.7B-Q2_0.gguf` | speed/quality baseline |
| `bonsai4b` | Ternary-Bonsai | 4B params | `Q2_0` | ~1 GB | `/data/data/com.termux/files/home/models/Ternary-Bonsai-4B-Q2_0.gguf` | likely best Bonsai candidate |
| `bonsai8b` | Ternary-Bonsai | 8B params | `Q2_0` | pending | `/data/data/com.termux/files/home/models/Ternary-Bonsai-8B-Q2_0.gguf` | crash-risk candidate |

For GitHub readability, benchmark results should prefer narrow, row-oriented
tables instead of very wide matrices. The durable analytics artifact should be
the flat CSV/TSV/ODS export, where each result row contains one model, one
phase, one batch shape, one KV setting, and one measured throughput.

## What `ctk` And `ctv` Mean

`-ctk` is short for `--cache-type-k`. It sets the data type used for the K
side of the KV cache.

`-ctv` is short for `--cache-type-v`. It sets the data type used for the V
side of the KV cache.

In transformer attention, each processed token leaves behind key and value
vectors. Future tokens attend over those cached vectors. On long sessions, this
KV cache becomes a large working set, so its data type can affect memory
pressure, speed, and sometimes quality.

Allowed cache types in this source tree are:

```text
f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1
```

There is no `f8` cache type exposed by `-ctk` / `-ctv` in this build. If an
`f8` row is desired later, it needs a runtime that actually exposes an f8 KV
cache type first. `q8_0` is 8-bit quantized cache, not f8 floating point.

Important implementation detail: quantized V-cache currently requires flash
attention. That means `-ctv q8_0 -fa 0` is expected to fail. The earlier q8/q8
raw row was therefore not a valid q8/q8 speed test; it was a useful discovery
about option compatibility.

## Phase 1: Smaller Microbatches At Larger Batch

Question: does the `768/64` win survive when microbatch is smaller, and does
`1024` need a smaller microbatch to become useful?

Primary XL rows:

```text
-b 768  -ub 16
-b 768  -ub 24
-b 768  -ub 32
-b 768  -ub 48
-b 768  -ub 64
-b 1024 -ub 16
-b 1024 -ub 24
-b 1024 -ub 32
-b 1024 -ub 48
-b 1024 -ub 64
```

Fixed flags:

```text
-dev Vulkan0 -ngl 99 -t 2 -fa 0 -p 512 -n 32 -d 0 -ctk f16 -ctv f16
```

Interpretation:

- If `768/32` or `768/48` gets close to `768/64`, it may be a safer server
  default.
- If `1024/32` or `1024/48` beats `768/64`, then `1024` is still alive as a
  candidate.
- If all smaller microbatches lose badly, keep `768/64` as the main profile
  and stop spending time below `ub=64`.

Repeat the full next-phase synthetic pass across the five-model set where
practical. If the 8B Bonsai model crashes `llama-server`, keep the failure row
in the data instead of hiding it; crash behavior is part of the day-to-day
viability comparison.

## Phase 2: KV Cache Compatibility And Speed

Question: is q8 KV useful when tested with the flash-attention setting it
requires?

Primary XL rows at context depth 4096:

```text
-fa 0 -ctk f16  -ctv f16
-fa 1 -ctk f16  -ctv f16
-fa 1 -ctk q8_0 -ctv q8_0
-fa 0 -ctk q8_0 -ctv f16
-fa 1 -ctk q8_0 -ctv f16
```

Fixed shape:

```text
-dev Vulkan0 -ngl 99 -t 2 -p 0 -n 128 -d 4096 -b 768 -ub 64
```

Interpretation:

- Compare `f16/f16` with `-fa 0` and `-fa 1` first. If flash attention itself
  slows this model down, q8/q8 has to beat that penalty before it matters.
- `q8/q8` is the real memory-pressure candidate, but it should only be used if
  it starts cleanly and does not damage decode speed too much.
- `q8 K / f16 V` is the fallback mixed row. It worked before with `-fa 0`, but
  was slower than f16/f16 in the first pass.

Repeat the viable KV rows at `-d 8192` only if the 4096-depth results are
competitive.

## Phase 3: Server-Session Confirmation

Once Phase 1 and Phase 2 identify the best synthetic rows, test server behavior
on the primary XL model only.

Minimum server rows:

```text
-c 4096 -b 512 -ub 64  -fa 0 -ctk f16 -ctv f16
-c 4096 -b 768 -ub 64  -fa 0 -ctk f16 -ctv f16
-c 8192 -b 768 -ub 64  -fa 0 -ctk f16 -ctv f16
```

Add a q8 KV server row only if Phase 2 shows a clean win or a memory-pressure
reason to use it.

For each row, collect:

- short generation: 128 tokens;
- medium generation: 512 tokens;
- long generation: 1024 tokens;
- one follow-up prompt after the long generation;
- time to first token;
- prompt-processing speed;
- early, middle, and late decode speed;
- server stderr lines for KV cache size, cache type, batch, ubatch, and slots.

The output of this phase should be a recommendation, not just a table:

- default interactive profile;
- conservative fallback;
- long-context profile if 8192 is worth keeping;
- whether q8 KV has any role on this Mali-G715 runtime.

## Runner

The synthetic follow-up rows are captured in:

```text
scripts/run_mali_gemma_next_phase_sweep.sh
```

The default `MODEL_SET` includes Gemma XL, Gemma Q4_K_M, Bonsai 1.7B, Bonsai
4B, and Bonsai 8B. Override `MODEL_SET` only for targeted reruns.

Flatten raw JSON artifacts into analytics-friendly files with:

```text
scripts/flatten_llama_bench_sweep.py OUT_DIR/summary.tsv --out-prefix docs/benchmarks/artifacts/<run-name>-flat
```

This writes:

```text
<run-name>-flat.csv
<run-name>-flat.tsv
<run-name>-flat.ods
```

Use CSV/TSV for scripts and data frames, and ODS for spreadsheet inspection.
