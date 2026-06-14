# Mali-G715 Gemma 4 E2B Agent Sweeps

Date: 2026-06-14

## Purpose

This plan defines the next measurements for Gemma 4 E2B and Bonsai agent
workflows on the Pixel 9 Pro Fold / Tensor G4 / Mali-G715 Vulkan path.

The primary model for the next sweeps is:

```text
/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
```

Comparison models:

```text
/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf
/data/data/com.termux/files/home/models/Ternary-Bonsai-1.7B-Q2_0.gguf
```

The current best measured synthetic profile is:

```text
-dev Vulkan0 -ngl 99 -t 2 -fa 0 -b 512 -ub 64
```

The next goal is to find a practical long-session agent profile for the primary
`UD-Q4_K_XL` model, then compare it against the Q4_K_M Gemma candidate and the
Bonsai baseline. The target is 15 tok/s if possible, and 20 tok/s if the
hardware/runtime path can support it without destroying agent quality.

## Why This Data Is Useful

Mobile local-LLM performance data is usually hard to compare because reports
often omit the exact model quant, runtime commit, Vulkan feature flags, context
length, prompt size, generation length, cache behavior, and thermal state.

This benchmark series is useful if it preserves those details. It can become a
reference for:

- Mali-G715 Vulkan behavior on a real phone-class SoC;
- Gemma 4 E2B `UD-Q4_K_XL` viability for local agent workflows;
- how the primary Gemma model compares with the Q4_K_M Gemma candidate and
  Bonsai 1.7B `Q2_0`;
- batch and microbatch tuning on unified-memory mobile GPUs;
- long-session context and KV-cache tradeoffs;
- differences between synthetic `llama-bench` throughput and interactive
  `llama-server` agent behavior.

The most publishable result will not be one fastest row. It will be a map of
which settings help, which settings hurt, and where the long-session slowdown
starts.

## Baseline To Keep Fixed

Use this as the control row unless the sweep explicitly changes it:

```text
model=/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
backend=Vulkan
device=Vulkan0
ngl=99
threads=2
flash_attn=off
batch=512
ubatch=64
kv=f16/f16
np=1
```

Record these for every sweep:

- model path, model size, model parameters, quant type, and model SHA256 if
  affordable;
- runtime binary path and commit/build label;
- `llama-bench --list-devices` output;
- `int dot`, `fp16`, UMA/shared memory, cooperative-matrix support;
- context length;
- prompt tokens, generation tokens, total tokens, and prompt characters;
- batch, microbatch, threads, GPU layers, flash attention, KV type;
- wall time, prompt-processing tok/s, token-generation tok/s;
- battery level, charging state, screen state, and device temperature if
  available. These are secondary for now; raw performance rows come first.

## Model Set

Run each planned sweep against these models unless a row fails to load or
exceeds practical runtime:

| Role | Model | Path |
| --- | --- | --- |
| Primary | Gemma 4 E2B `UD-Q4_K_XL` | `/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf` |
| Comparison | Gemma 4 E2B `Q4_K_M` | `/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf` |
| Baseline | Ternary-Bonsai 1.7B `Q2_0` | `/data/data/com.termux/files/home/models/Ternary-Bonsai-1.7B-Q2_0.gguf` |

Keep `-t 2` for all of these sweeps. Thread count is not part of the next
measurement round.

## Sweep 1: Context Length

Question: what is the smallest context that preserves agent quality without
unnecessary KV-cache and attention cost?

```text
-c 2048  -b 512 -ub 64
-c 4096  -b 512 -ub 64
-c 6144  -b 512 -ub 64
-c 8192  -b 512 -ub 64
```

For Gemma 4 E2B, the current KV-size annotation is:

```text
KV bytes/token = 71,680 bytes ~= 70 KiB/token
```

Approximate f16 KV cache size:

| Context | KV cache |
| ---: | ---: |
| 2,048 | 140 MiB |
| 4,096 | 280 MiB |
| 6,144 | 420 MiB |
| 8,192 | 560 MiB |
| 16,384 | 1.09 GiB |
| 32,768 | 2.19 GiB |

Publishable result:

- recommended interactive context;
- where decode slowdown becomes visible;
- whether `4096 + summarization` beats larger raw context.

## Sweep 2: Larger Logical Batch

Question: does the Mali-G715 path keep improving with larger logical batch when
microbatch stays at 64?

```text
-b 512  -ub 64
-b 768  -ub 64
-b 1024 -ub 64
```

Stop early if context creation fails, memory pressure rises sharply, or thermal
state makes the result unusable.

Publishable result:

- whether `512/64` is the actual knee;
- whether higher logical batch helps prompt processing without hurting decode;
- whether larger batches increase memory pressure or instability.

## Sweep 3: Microbatch Around 64

Question: is `-ub 64` the true local optimum, or just the best value tested so
far?

```text
-b 512 -ub 48
-b 512 -ub 64
-b 512 -ub 80
-b 512 -ub 96
```

Optional follow-up only if `768/64` works:

```text
-b 768 -ub 48
-b 768 -ub 64
-b 768 -ub 80
```

Publishable result:

- whether microbatch 64 is a hardware sweet spot;
- whether the cliff begins before 128;
- whether larger logical batches alter the microbatch optimum.

## Sweep 4: Server-Session Long-Context Behavior

Question: why do long qualitative agent sessions slow down, then feel nominal
again after a follow-up prompt?

Use `llama-server`, not only `llama-bench`.

Rows:

```text
-c 4096 -b 512 -ub 64
-c 8192 -b 512 -ub 64
```

For each row, run:

- short completion: 128 generated tokens;
- medium completion: 512 generated tokens;
- long completion: 1024 generated tokens;
- follow-up prompt after the long completion.

Collect:

- time to first token;
- prompt-processing time;
- decode tok/s during early, middle, and late generation;
- total wall time;
- whether follow-up prompt restores speed;
- server slot/cache logs;
- `--cache-ram 0` versus default cache behavior.

Publishable result:

- whether slowdown is mostly decode-over-growing-context, cache behavior,
  thermal state, or slot/prefix reuse;
- recommended long-session strategy.

## Sweep 5: KV Cache Type

Question: can q8 KV reduce memory pressure without damaging quality or failing
context creation?

This is a KV-cache representation sweep, not a model-quant-variant sweep. The
model set stays fixed to the three listed files.

Current evidence:

```text
q4 KV failed to create context for the 512/64 row.
```

Next rows:

```text
f16/f16 baseline
q8/q8 if supported
q8 key / f16 value if supported
```

Publishable result:

- whether q8 KV is viable on this build/device;
- whether q8 improves long-context stability or speed;
- whether failures are model-specific, runtime-specific, or option-specific.

## Sweep 6: Thermal And Power State

Question: how much of the throughput curve is hardware throttling rather than
runtime tuning?

This is secondary for the immediate round. Collect thermal/power notes when
easy, but do not block raw performance collection on perfect thermal
instrumentation.

Run the same baseline in controlled states:

```text
cool start, unplugged, screen on
cool start, plugged in, screen on
warm repeated run, plugged in, screen on
screen off or dimmed if the workflow allows it
```

Collect:

- battery temperature;
- skin/device temperature if available;
- battery percentage;
- charging state;
- wall-clock time since previous run;
- whether Android kills or deprioritizes Termux.

Publishable result:

- sustained tok/s, not just burst tok/s;
- recommended benchmark discipline for phone-class local LLM testing.

## Sweep 7: Prompt And Tooling Overhead

Question: how much performance is being lost to prompt bulk rather than model
speed?

Compare these prompt shapes:

```text
minimal system prompt
current agent prompt
current agent prompt plus tool schemas
current agent prompt plus long tool-output history
summarized long-session prompt
```

Collect:

- prompt characters;
- prompt tokens;
- time to first token;
- prompt-processing tok/s;
- generation tok/s;
- qualitative tool-following quality.

Publishable result:

- cost of agent scaffolding in tokens and seconds;
- whether rolling summaries are more effective than increasing `-c`;
- a practical prompt-budget recommendation.

## Sweep 8: Runtime Comparison

Question: does the QVAC/Fabric fork become competitive once it has an Android
Vulkan artifact with integer-dot shader support?

Compare:

```text
current PrismML Android Vulkan artifact
QVAC/Fabric Android Vulkan artifact from PR #151 or local equivalent
newer upstream llama.cpp/PrismML artifact if available
```

Use the same primary Gemma 4 E2B `UD-Q4_K_XL` model and best-known
context/batch profile.

Publishable result:

- whether QVAC/Fabric adds useful runtime speed on Mali-G715;
- whether its tuning and mobile-GPU ideas translate to this Gemma path;
- whether the fork should be mined for patches or used as a runtime.

## Minimum Publishable Dataset

Before raising awareness, collect at least:

1. Context sweep: `2048`, `4096`, `6144`, `8192`.
2. Batch sweep: `512/64`, `768/64`, `1024/64`.
3. Microbatch sweep: `512/48`, `512/64`, `512/80`, `512/96`.
4. Server-session sweep: short, medium, long, and follow-up generations.
5. The same rows across the primary Gemma `UD-Q4_K_XL`, Gemma `Q4_K_M`, and
   Bonsai `Q2_0` model set where practical.
6. One prompt/tool-overhead comparison.
7. One PrismML versus QVAC/Fabric runtime comparison when the QVAC int-dot
   artifact is available.
8. One clear recommended profile and one conservative fallback profile.

## Current Hypothesis

The likely best practical path is:

```text
-c 4096 or -c 6144
-b 512 or -b 768
-ub near 64
-t 2
--flash-attn off
f16 KV unless q8 KV proves stable
shorter prompt/tool context with rolling summaries
```

The 15-20 tok/s goal may require more than parameter tuning. It may need a
newer Vulkan backend, better shader paths, or tighter agent prompt discipline.
The strongest near-term win is likely reducing prompt and long-session context
load while preserving enough memory through summaries and retrieval.

## F16 Versus Q8 KV

`f16` stores each KV-cache number as a 16-bit floating-point value. It uses more
memory, but it is the safer quality baseline and the path already known to work
for these rows.

`q8` stores each KV-cache number in an 8-bit quantized representation plus
scale metadata. It usually cuts KV memory roughly in half, which can help
longer contexts or reduce memory pressure. The tradeoff is possible quality
loss, extra quantize/dequantize overhead, and implementation-specific support
issues. That is why q8 KV should be tested as a targeted follow-up against f16,
not assumed to be faster.

In short:

```text
f16 KV = larger cache, safer baseline, usually lower risk.
q8 KV  = smaller cache, possible memory win, must be tested for quality/speed.
```
