# Mali-G715 Gemma Agent Raw Sweep

Date: 2026-06-14

This is the first raw-number pass for the corrected three-model agent sweep.
It uses synthetic `llama-bench` measurements to map model, context depth,
logical batch, microbatch, and KV-cache behavior before running longer
`llama-server` session tests.

Raw local artifacts:

```text
/data/data/com.termux/files/home/benchmarks/mali-g715-gemma-agent-grouped-sweep-20260614T203751Z/
```

Runner:

```text
scripts/run_mali_gemma_agent_grouped_sweep.sh
```

Committed phase summary:

```text
docs/benchmarks/artifacts/mali-g715-gemma-agent-grouped-sweep-20260614T203751Z-summary.tsv
```

## Runtime

```text
device=Pixel 9 Pro Fold
platform=zumapro
gpu=Mali-G715
runtime=/data/data/com.termux/files/home/android-arm64-vulkan
llama-bench build_commit=12b7c38
threads=2
ngl=99
device_arg=Vulkan0
flash_attn=0
repeat=1
```

`llama-bench --list-devices` reported:

```text
ggml_vulkan: 0 = Mali-G715 (Mali-G715) | uma: 1 | fp16: 1 | bf16: 0 | warp size: 16 | shared memory: 32768 | int dot: 1 | matrix cores: KHR_coopmat
Available devices:
  Vulkan0: Mali-G715 (15455 MiB, 15455 MiB free)
```

Battery state at start was plugged AC, charging, 45%, 39.9 C. Thermal data was
not controlled in this pass; treat this as a raw exploratory sweep, not the
final repeatable publication set.

## Model Set

| Label | Model | Path |
| --- | --- | --- |
| `primary_xl` | Gemma 4 E2B `UD-Q4_K_XL` | `/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf` |
| `q4km` | Gemma 4 E2B `Q4_K_M` | `/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf` |
| `bonsai1p7b` | Ternary-Bonsai 1.7B `Q2_0` | `/data/data/com.termux/files/home/models/Ternary-Bonsai-1.7B-Q2_0.gguf` |

All rows used full Vulkan offload, `-t 2`, `-fa 0`, and `-r 1`.

## Baseline

Shape:

```text
-p 512 -n 32 -d 0 -b 512 -ub 64 -ctk f16 -ctv f16
```

| Model | PP 512 tok/s | TG 32 tok/s |
| --- | ---: | ---: |
| `primary_xl` | 25.67 | 8.46 |
| `q4km` | 23.57 | 6.82 |
| `bonsai1p7b` | 30.77 | 14.11 |

The primary XL model is faster than Q4_K_M on this runtime in both prompt
processing and short decode, while Bonsai remains much faster at decode but is
not the preferred agent-quality model.

## Context Depth

Shape:

```text
-p 0 -n 128 -d 0,2048,4096,6144,8192 -b 512 -ub 64 -ctk f16 -ctv f16
```

| Model | d0 | d2048 | d4096 | d6144 | d8192 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `primary_xl` | 6.60 | 8.85 | 8.49 | 7.74 | 7.26 |
| `q4km` | 5.82 | 7.74 | 7.45 | 6.77 | 6.62 |
| `bonsai1p7b` | 10.12 | 14.73 | 12.91 | 11.32 | 9.93 |

The Gemma rows show a gradual long-context decode decline after 4096 depth, not
a cliff. For the primary XL model, 4096 remains a good default target; 8192 is
viable but costs more wall time and decode headroom.

## Larger Logical Batch

Shape:

```text
-p 512 -n 32 -d 0 -b 512,768,1024 -ub 64 -ctk f16 -ctv f16
```

| Model | b512 PP | b512 TG | b768 PP | b768 TG | b1024 PP | b1024 TG |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `primary_xl` | 25.38 | 8.49 | 36.83 | 8.56 | 36.80 | 8.92 |
| `q4km` | 23.91 | 7.12 | 35.35 | 7.79 | 35.36 | 7.82 |
| `bonsai1p7b` | 30.89 | 14.04 | 46.33 | 15.94 | 46.38 | 15.98 |

`768/64` looks like the next better prompt-ingestion profile for all three
models. `1024/64` is not meaningfully better for prompt processing than
`768/64`, but it may slightly improve short decode in this synthetic shape.

## Microbatch Around 64

Shape:

```text
-p 512 -n 32 -d 0 -b 512 -ub 48,64,80,96 -ctk f16 -ctv f16
```

| Model | ub48 PP | ub48 TG | ub64 PP | ub64 TG | ub80 PP | ub80 TG | ub96 PP | ub96 TG |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `primary_xl` | 19.94 | 8.47 | 36.86 | 9.02 | 5.77 | 9.04 | 6.95 | 9.04 |
| `q4km` | 18.32 | 7.13 | 35.37 | 7.83 | 5.61 | 7.91 | 6.80 | 7.83 |
| `bonsai1p7b` | 24.10 | 14.03 | 46.40 | 16.13 | 7.28 | 16.10 | 8.79 | 15.86 |

This strongly supports `-ub 64` as the practical microbatch knee. Higher
microbatch values keep short decode similar but collapse prompt processing.

## KV Cache Type

Shape:

```text
-p 0 -n 128 -d 4096 -b 512 -ub 64
```

| Model | f16/f16 TG | q8/q8 with `-fa 0` | q8 key / f16 value TG |
| --- | ---: | --- | ---: |
| `primary_xl` | 8.34 | failed to create context | 7.25 |
| `q4km` | 7.28 | failed to create context | 6.76 |
| `bonsai1p7b` | 12.31 | failed to create context | aborted after 623s |

Full q8 KV is not viable in this exact `-fa 0` configuration because quantized
V-cache requires flash attention in the current source tree. q8 key with f16
value works for both Gemma models with flash attention off, but it is slower
than f16/f16 in the first raw pass. The next KV follow-up should test q8/q8
with `-fa 1` before treating it as unsupported on this device.

## First Conclusions

- The primary `UD-Q4_K_XL` model is the right main focus so far: it beats the
  Q4_K_M candidate on raw Gemma throughput in this run.
- `-b 768 -ub 64` is the best next interactive candidate. It captures most of
  the prompt-processing gain of `1024/64` without pushing the logical batch as
  high.
- `-ub 64` remains the best microbatch setting. `80` and `96` are bad prompt
  processors on this Mali-G715 path.
- `-c 4096` remains the conservative default. `8192` is viable for quality
  experiments, but the raw context-depth rows show lower decode headroom and
  much longer measurement wall time.
- q8/q8 KV should be treated as untested under its required flash-attention
  configuration. The failed raw row used `-fa 0`, which cannot support a
  quantized V cache in this source tree.
- q8 key / f16 value is not faster than f16/f16 on the Gemma models, so it is
  not a current speed path.

## Recommended Next Profile To Test In Server Mode

Use the primary XL model:

```text
-m /data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
-dev Vulkan0 -ngl 99 -t 2 -tb 2 -fa 0 -c 4096 -b 768 -ub 64
```

Fallback if server behavior is less stable than synthetic `llama-bench`:

```text
-c 4096 -b 512 -ub 64
```

Next benchmark stage should be `llama-server` session behavior for the primary
XL model at `4096` and `8192`, comparing `512/64` against `768/64`.
