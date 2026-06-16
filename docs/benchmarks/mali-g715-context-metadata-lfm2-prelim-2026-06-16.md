# Mali-G715 Context Metadata And LFM2 Preliminary Profile

Date: 2026-06-16

This note records each local model's advertised GGUF context length and starts
tracking the context/depth shape used by every new benchmark run. It also adds
the first focused LFM2 8B A1B profile before expanding that model into a wider
comparison.

## Raw Artifacts

```text
/data/data/com.termux/files/home/benchmarks/mali-g715-model-context-metadata-20260616T033611Z/
/data/data/com.termux/files/home/benchmarks/mali-g715-lfm2-8b-a1b-prelim-20260616T034157Z/
```

Committed analytics exports:

```text
docs/benchmarks/artifacts/mali-g715-model-context-metadata-20260616T033611Z.tsv
docs/benchmarks/artifacts/mali-g715-model-context-metadata-20260616T033611Z.csv
docs/benchmarks/artifacts/mali-g715-model-context-metadata-20260616T033611Z.ods
docs/benchmarks/artifacts/mali-g715-lfm2-8b-a1b-prelim-20260616T034157Z-summary.tsv
docs/benchmarks/artifacts/mali-g715-lfm2-8b-a1b-prelim-20260616T034157Z-flat.csv
docs/benchmarks/artifacts/mali-g715-lfm2-8b-a1b-prelim-20260616T034157Z-flat.tsv
docs/benchmarks/artifacts/mali-g715-lfm2-8b-a1b-prelim-20260616T034157Z-flat.ods
```

## GGUF Context Metadata

These values come from verbose `llama-bench` load logs, specifically the
`*.context_length` metadata and the printed `n_ctx_train` line. They are model
capacity metadata, not a statement that every context size is practical on this
phone.

| Label | Architecture | GGUF context | Original context | File GB | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| `primary_xl` | `gemma4` | 131072 | 131072 | 2.62 | matches the successful 128k Gemma session |
| `q4km` | `gemma4` | 131072 | 131072 | 3.11 | same trained context family as XL |
| `bonsai1p7b` | `qwen3` | 32768 | 8192 | 0.46 | rope-scaled beyond original 8k |
| `bonsai4b` | `qwen3` | 32768 | 8192 | 1.07 | conversationally useful, weak tool calling versus Gemma |
| `bonsai8b` | `qwen3` | 65536 | 16384 | 2.18 | larger window, but slow and server stability remains suspect |
| `lfm2_8b_a1b` | `lfm2moe` | 128000 | 128000 | 4.73 | MoE candidate; tested separately below |

## Context Used By Current Runs

`llama-bench` does not use the same `-c/--ctx-size` server flag. In these
synthetic reports, the important context field is `-d/--n-depth`, which
pre-fills the KV cache before generation. For server confirmation runs, record
the real `-c` value separately.

| Report | Benchmark shape | Context/depth used | Server ctx equivalent | Export status |
| --- | --- | ---: | ---: | --- |
| Gemma/Bonsai baseline | `-p 512 -n 32 -d 0` | no long-context prefill | not set | regenerated with derived context columns |
| Q8/Q8 KV FA1 | `-p 0 -n 128 -d 4096` | 4096 | about 4096 | regenerated with derived context columns |
| LFM2 preliminary baseline | `-p 512 -n 32 -d 0` | no long-context prefill | 4096 target | new CSV/TSV/ODS exports |
| LFM2 preliminary 4k | `-p 0 -n 128 -d 4096` | 4096 | 4096 target | new CSV/TSV/ODS exports |

The flattened export schema now includes:

```text
benchmark_context_tokens
benchmark_work_tokens
server_ctx_size
```

`benchmark_context_tokens` is the synthetic depth for long-context rows, or the
prompt/generation token count for short rows. `benchmark_work_tokens` is the
tokens actively processed by the row. `server_ctx_size` is reserved for real
server runs or benchmark wrappers that explicitly set the intended server
context.

## LFM2 8B A1B Preliminary Profile

Model:

```text
/data/data/com.termux/files/home/models/LFM2-8B-A1B-Q4_0.gguf
```

Runtime shape:

```text
-t 2 -ngl 99 -dev Vulkan0 -fa 0 -ctk f16 -ctv f16 -b 512 -ub 64
```

| Phase | Prompt | Gen | Depth | PP tok/s | TG tok/s | Seconds | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `baseline_512_64` | 512 | 32 | 0 | 11.11 | 10.17 | 57 | completed |
| `ctx4096_512_64` | 0 | 128 | 4096 |  | 12.55 | 259 | completed |

## Read

The LFM2 model loaded and completed both preliminary rows cleanly, including
the 4k-depth KV row. That is a better first signal than the earlier manual
trouble suggested.

The short prompt-processing rate is not competitive with the smaller Gemma
Q4_K_M prompt rows, but the decode rate is strong enough to justify a separate
MoE follow-up. Keep it out of the Gemma/Bonsai default comparison until it gets
its own server-load and qualitative agent pass, because MoE behavior and memory
pressure may differ from the dense models.

Moving forward, every benchmark report should state both:

- the model's advertised GGUF context length;
- the context/depth actually used by the run.
