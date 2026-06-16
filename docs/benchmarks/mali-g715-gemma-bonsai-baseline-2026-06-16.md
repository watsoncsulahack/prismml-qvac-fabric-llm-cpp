# Mali-G715 Gemma/Bonsai Baseline

Date: 2026-06-16

This is the first five-model baseline after adding the Ternary-Bonsai 4B and
8B models. The LFM2 8B A1B model is intentionally held for a later MoE-specific
comparison.

Raw local artifacts:

```text
/data/data/com.termux/files/home/benchmarks/mali-g715-gemma-next-phase-baseline-20260616T014804Z/
```

Committed analytics exports:

```text
docs/benchmarks/artifacts/mali-g715-gemma-next-phase-baseline-20260616T014804Z-flat.csv
docs/benchmarks/artifacts/mali-g715-gemma-next-phase-baseline-20260616T014804Z-flat.tsv
docs/benchmarks/artifacts/mali-g715-gemma-next-phase-baseline-20260616T014804Z-flat.ods
```

## Runtime

```text
device=Pixel 9 Pro Fold
gpu=Mali-G715
runtime=/data/data/com.termux/files/home/android-arm64-vulkan
threads=2
ngl=99
device_arg=Vulkan0
flash_attn=0
repeat=1
kv=f16/f16
```

`llama-bench --list-devices` reported:

```text
ggml_vulkan: 0 = Mali-G715 (Mali-G715) | uma: 1 | fp16: 1 | bf16: 0 | warp size: 16 | shared memory: 32768 | int dot: 1 | matrix cores: KHR_coopmat
Available devices:
  Vulkan0: Mali-G715 (15455 MiB, 15455 MiB free)
```

## Model Set

| Label | Family | Size class | Quant | File GB | Params B | Path |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `primary_xl` | Gemma 4 E2B | 4.63B | `UD-Q4_K_XL` | 2.60 | 4.63 | `/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf` |
| `q4km` | Gemma 4 E2B | 4.65B | `Q4_K_M` | 3.09 | 4.65 | `/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf` |
| `bonsai1p7b` | Ternary-Bonsai | 1.72B | `Q2_0` | 0.46 | 1.72 | `/data/data/com.termux/files/home/models/Ternary-Bonsai-1.7B-Q2_0.gguf` |
| `bonsai4b` | Ternary-Bonsai | 4.02B | `Q2_0` | 1.07 | 4.02 | `/data/data/com.termux/files/home/models/Ternary-Bonsai-4B-Q2_0.gguf` |
| `bonsai8b` | Ternary-Bonsai | 8.19B | `Q2_0` | 2.18 | 8.19 | `/data/data/com.termux/files/home/models/Ternary-Bonsai-8B-Q2_0.gguf` |

## Baseline Results

Shape:

```text
-p 512 -n 32 -d 0 -t 2 -ngl 99 -fa 0 -ctk f16 -ctv f16
```

This table is intentionally narrow and row-oriented for GitHub scrolling. Use
the CSV/TSV/ODS artifacts for filtering, pivoting, and plotting.

| Model | Shape | PP tok/s | TG tok/s | Seconds | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| `primary_xl` | `512/64` | 19.54 | 5.12 | 37 | lower than prior raw pass; treat as run-specific until repeated |
| `primary_xl` | `768/64` | 16.62 | 7.84 | 40 | decode improved, prompt processing regressed in this pass |
| `q4km` | `512/64` | 26.56 | 7.40 | 29 | strongest Gemma prompt row in this pass |
| `q4km` | `768/64` | 25.01 | 7.10 | 30 | no clear 768 win here |
| `bonsai1p7b` | `512/64` | 33.94 | 14.30 | 20 | fastest decode in this set |
| `bonsai1p7b` | `768/64` | 35.48 | 13.58 | 19 | modest prompt gain |
| `bonsai4b` | `512/64` | 16.61 | 7.79 | 38 | similar short decode to Gemma, much smaller file |
| `bonsai4b` | `768/64` | 16.41 | 6.43 | 39 | 768 did not help in this pass |
| `bonsai8b` | `512/64` | 8.55 | 4.26 | 72 | slow synthetic row; server-crash concern still relevant |
| `bonsai8b` | `768/64` | 9.19 | 4.72 | 67 | slight improvement, still slow |

## Initial Read

The Bonsai 4B model is the most interesting new candidate. It is close to the
Gemma short-decode range in this synthetic row while using about 1.07 GB on
disk versus 2.60 GB for the Gemma XL file. That makes it worth a qualitative
agent test, especially if its tool-following and instruction quality are good
enough.

Bonsai 8B did not crash `llama-bench`, but the row is slow enough that the
reported `llama-server` instability should be treated as a real viability
issue. Small file size alone is not sufficient for day-to-day agent use.

This run should not overwrite the earlier Gemma conclusion by itself. The Gemma
XL numbers were lower than the 2026-06-14 raw sweep, so repeatability and
thermal/session state need to be considered before changing the recommended
Gemma profile.

## Qualitative Long-Context Note

Allan reported a successful 128k-context Gemma 4 E2B QAT Pi-agent session while
debugging a remote Node server. The session reached roughly 60% of the total
context window and slowed to about 3 tok/s near the end. The useful workflow was
a handoff: the agent carried the investigation deep into the problem, then Allan
took over manual edits and reran the computer-side workflow to finish the task.

That is an important practical result: very long context may be worth the speed
cost when it lets the agent preserve enough working state to get the task close
to done, even if the final mile is a human handoff.
