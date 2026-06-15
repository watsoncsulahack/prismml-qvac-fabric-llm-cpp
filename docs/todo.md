# TODO

This file tracks the experiment plan for the PrismML/QVAC Android Vulkan work.
The README should stay focused on current status and reproducible results; the
planning notes live here.

## Completed

### 1. Make the GitHub Actions Android artifact report `int dot: 1`

Goal: the CI-built Android arm64 Vulkan artifact should match the native Termux
PrismML and QVAC binaries on the Pixel 9 Pro Fold:

```text
Mali-G715 | fp16: 1 | int dot: 1 | matrix cores: KHR_coopmat
```

The working theory is that the old Actions artifact used shaderc `glslc`, whose
Ubuntu package did not compile the `GL_EXT_integer_dot_product` feature-test
shader. That made CMake generate Vulkan shaders without
`GGML_VULKAN_INTEGER_DOT_GLSLC_SUPPORT`, even though the phone runtime exposes
the Vulkan integer-dot feature.

The completed fix uses the LunarG Vulkan SDK `glslc` for Android shader
compilation and copies the full SDK include tree into the Android NDK sysroot.
This keeps llama.cpp's shader feature probes working while giving the Android
cross-build a compiler that supports `GL_EXT_integer_dot_product`.

Acceptance checks:

- [x] GitHub Actions Android arm64 Vulkan job succeeds.
- [x] Downloaded Android artifact runs in native Termux.
- [x] `llama-bench --list-devices` reports `int dot: 1` on `Vulkan0`.
- [x] Bonsai `Q2_0` smoke benchmark completes without the old descriptor-set
  crash.

Evidence:

- Build commit: `e2a636e`
- Benchmark/report commit: `06a6dfa`
- Actions run:
  <https://github.com/watsoncsulahack/prismml-qvac-fabric-llm-cpp/actions/runs/26809874917>
- Runtime proof:
  `Mali-G715 | fp16: 1 | int dot: 1 | matrix cores: KHR_coopmat`
- Bonsai `Q2_0` smoke report:
  [actions-android-arm64-vulkan-q2-bonsai-smoke-2026-06-02.md](../reports/actions-android-arm64-vulkan-q2-bonsai-smoke-2026-06-02.md)
- Smaller Bonsai `Q2_0` smoke report:
  [actions-android-arm64-vulkan-q2-bonsai-1p7b-smoke-2026-06-04.md](../reports/actions-android-arm64-vulkan-q2-bonsai-1p7b-smoke-2026-06-04.md)

Most recent smoke results with `-p 64 -n 64 -r 1 -dev Vulkan0 -ngl 99`:

| Model | pp tok/s | tg tok/s | Result |
| --- | ---: | ---: | --- |
| Bonsai 1.7B `Q2_0` | 47.70 | 17.92 | pass |
| Bonsai 4B `Q2_0` | 20.30 | 7.76 | pass |
| Bonsai 8B `Q2_0` | 10.70 | 4.72 | pass |

### 1.1. Quantify Gemma 4 E2B batch/microbatch sweep

Gemma 4 E2B Q4_K_M was benchmarked after qualitative Pi-session assessment
showed the new batch settings felt much better than the Bonsai model.

Evidence:

- Report:
  [mali-g715-gemma4-e2b-q4km-batch-sweep-2026-06-14.md](benchmarks/mali-g715-gemma4-e2b-q4km-batch-sweep-2026-06-14.md)
- Best measured row: `-ngl 99 -t 2 -fa 0 -b 512 -ub 64`
- Result: `32.41` PP tok/s, `7.93` TG tok/s, `65s` wall time
- Interpretation: for Gemma 4 E2B, `512/64` is the current best interactive
  default. `512/128` regressed to `8.24` PP tok/s, `6.51` TG tok/s, and `206s`
  wall time, so larger logical batch helped while larger microbatch hurt.
- Targeted follow-up: `-t 1`, `-t 4`, flash attention, and q4 KV did not beat
  `-t 2 --flash-attn off` with f16 KV. q4 KV failed to create context in the
  `512/64` row.
- QVAC/Fabric assessment: the local checkout and available Android server
  binaries are stale for this Gemma path; the tested QVAC server reports
  `int dot: 0` on Mali-G715, while the current PrismML artifact reports
  `int dot: 1`. Treat QVAC as a source of tuning ideas, not the primary Gemma
  runtime until it is rebased and benchmarked.

## Active Focus

### 1.2. Publishable Gemma 4 E2B agent tuning dataset

The next benchmark plan is captured in:

[mali-g715-gemma4-e2b-agent-sweeps-2026-06-14.md](benchmarks/mali-g715-gemma4-e2b-agent-sweeps-2026-06-14.md)

Primary model:

```text
/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
```

Comparison models:

```text
/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf
/data/data/com.termux/files/home/models/Ternary-Bonsai-1.7B-Q2_0.gguf
```

Minimum dataset before publishing:

- context sweep: `2048`, `4096`, `6144`, `8192`;
- larger-batch sweep: `512/64`, `768/64`, `1024/64`;
- microbatch-near-64 sweep: `512/48`, `512/64`, `512/80`, `512/96`;
- server-session sweep with short, medium, long, and follow-up generations;
- the same rows across the three-model set where practical;
- raw performance numbers first, with thermal and power-state notes collected
  opportunistically;
- prompt/tool-overhead comparison;
- PrismML versus QVAC/Fabric runtime comparison when the QVAC int-dot artifact
  is available;
- final recommended profile and conservative fallback profile.

Initial raw synthetic sweep:
[mali-g715-gemma-agent-raw-sweep-2026-06-14.md](benchmarks/mali-g715-gemma-agent-raw-sweep-2026-06-14.md)

Next phase after the raw sweep:
[mali-g715-gemma-agent-next-phase-2026-06-15.md](benchmarks/mali-g715-gemma-agent-next-phase-2026-06-15.md)

Immediate next rows:

- primary XL `768` and `1024` logical batches with smaller microbatches
  `16`, `24`, `32`, `48`, and `64`;
- KV cache follow-up that explains `-ctk` and `-ctv`, confirms that this build
  has no f8 KV type, and retests q8/q8 with `-fa 1` because quantized V cache
  requires flash attention;
- server-session confirmation only after the synthetic follow-up narrows the
  profile.

### Current local model paths

Larger models are stored under top-level Termux `~/models`:

```text
/data/data/com.termux/files/home/models/gemma-4-12b-it-qat-q4_0.gguf
/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
/data/data/com.termux/files/home/models/LFM2-8B-A1B-Q4_0.gguf
```

Finish Bonsai sweep validation before moving to the LFM2 8B A1B MoE benchmark.

### 2. Build lightweight Vulkan profiling for Bonsai `Q2_0`

Question to answer: where does Bonsai `Q2_0` time go on Mali-G715?

Right now `llama-bench` gives end-to-end prompt-processing and token-generation
speed. That tells us whether the binary is faster, but not why. The profiler
task is to add enough timing inside the Vulkan backend to split one benchmark
run into useful buckets:

| Bucket | What it means | Why it matters |
| --- | --- | --- |
| Unpack/dequant | Time spent decoding packed `Q2_0` weight bytes into usable numeric values | Low-bit formats save memory bandwidth but can lose if decoding dominates |
| Matmul accumulation | Time spent doing the actual dot products / multiply-accumulate work | This is where integer-dot or better shader layouts should help |
| Attention / MLP dispatches | Time spent in the surrounding transformer kernels, not just `Q2_0` matmul | Avoid optimizing matmul if attention or MLP kernels are the real limit |
| Synchronization / submit overhead | CPU/GPU waits, command-buffer boundaries, barriers, and timing gaps | Mobile Vulkan can look slow because of scheduling overhead, not raw shader math |

Why this matters now:

- TODO #1 proved the fixed Actions artifact runs Bonsai `Q2_0` with `int dot: 1`.
- The 4B and 8B Q2_0 results are stable enough for smoke testing, but they still
  do not explain why low-bit Bonsai is not dramatically faster.
- The next bottleneck is no longer "does the binary build and run?" It is "which
  part of the Vulkan execution path is spending the time?"

Practical mental model:

1. The model file stores packed low-bit weights.
2. The Vulkan backend uploads those packed blocks and activations to GPU memory.
3. A shader dispatch reads a block, unpacks its 2-bit codes, applies the scale
   value, and turns those codes into usable numeric weights.
4. The shader multiplies those decoded weights by activation values and
   accumulates partial sums for matrix multiplication.
5. Other transformer kernels run around those matmuls: attention, feed-forward
   / MLP work, normalization, copies, and shape operations.
6. The CPU submits command buffers and sometimes waits for GPU work to finish.
   Barriers and command-buffer boundaries can add overhead even when the shader
   math itself is fast.

The profiler should make those stages visible enough to decide where to work
next. If unpack/dequant dominates, the Q2_0 shader layout is the target. If
matmul dominates, integer-dot/cooperative-matrix choices matter more. If
synchronization dominates, the work should focus on graph batching, barriers,
or command submission behavior instead of tensor math.

The thing to build is not a full UI profiler. It should be a small
instrumentation mode in this fork:

1. Add an opt-in runtime flag or environment variable, for example
   `GGML_VULKAN_PROFILE=1`, so normal benchmarks stay clean.
2. Wrap selected Vulkan graph operations with timestamp queries or coarse scoped
   timers. Prefer GPU timestamp queries where possible; use CPU-side timing only
   for submit/wait overhead.
3. Tag operations by shader/pipeline name so Bonsai `Q2_0` matmul work can be
   separated from unrelated Vulkan kernels.
4. Emit a machine-readable summary after `llama-bench`, for example JSONL or a
   compact Markdown table:

   ```text
   q2_0_unpack_dequant_ms
   q2_0_matmul_ms
   attention_ms
   mlp_ms
   sync_submit_wait_ms
   total_gpu_timed_ms
   ```

5. Run the same model/command before and after shader changes:

   ```sh
   ./llama-bench -m /path/to/Ternary-Bonsai-4B-Q2_0.gguf \
     -p 64 -n 64 -r 3 -dev Vulkan0 -ngl 99
   ```

Good first implementation target:

- Instrument only the Vulkan compute dispatch path enough to print per-pipeline
  elapsed time grouped by shader name.
- Then map the relevant shader names back to PrismML `Q2_0` matmul, attention,
  and MLP categories.

Concrete first patch:

- Add a tiny profiling accumulator in `ggml-vulkan.cpp`.
- Gate it behind `GGML_VULKAN_PROFILE=1`.
- Around each compute pipeline dispatch, record:
  - pipeline/shader name;
  - tensor op type where available;
  - elapsed GPU timestamp if available;
  - fallback CPU submit/wait timing if GPU timestamps are unavailable.
- At shutdown or graph completion, print grouped totals like:

  ```text
  pipeline=q2_0_matmul dispatches=123 gpu_ms=456.7 cpu_wait_ms=12.3
  pipeline=soft_max dispatches=45 gpu_ms=67.8 cpu_wait_ms=3.2
  ```

The first version does not need perfect category labels. Per-pipeline timing is
enough to identify which shader names matter, then the labels can be refined.

Out of scope for the first pass:

- Android Perfetto integration.
- Vendor-specific Arm GPU counters.
- A polished profiler UI.
- Refactoring the whole Vulkan backend.

### 3. Compare PrismML `Q2_0` shaders against QVAC `TQ2_0` shaders

Focus on the shader and tensor-layout differences that could explain why one
runtime behaves better than another:

- block layout;
- thread mapping;
- whether unpack/dequant is fused into matmul;
- subgroup usage;
- shared-memory usage;
- integer-dot usage.

This should stay as analysis until the CI artifact is working and the profiler
can show where time is actually going.

## Deferred

These are useful but not the current focus:

4. Decide the long-term base: keep improving this PrismML fork for Bonsai, or
   port PrismML `Q2_0` into QVAC for a stronger Android runtime base.
5. If porting into QVAC, add a distinct internal PrismML tensor type instead of
   reusing QVAC `TQ2_0`; implement CPU correctness first, then Vulkan.
6. Rerun publication-grade longer benchmarks, for example
   `-p 128 -n 128 -r 3`, after the binary/toolchain path is stable.
