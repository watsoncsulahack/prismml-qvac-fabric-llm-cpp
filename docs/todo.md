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

## Active Focus

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
