# TODO

This file tracks the experiment plan for the PrismML/QVAC Android Vulkan work.
The README should stay focused on current status and reproducible results; the
planning notes live here.

## Active Focus

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

The current fix is to compile Android Vulkan shaders through
`ci/glslc-glslang-wrapper.sh`, which preserves the `glslc` command shape that
llama.cpp expects while routing actual shader compilation through
`glslangValidator`.

Acceptance checks:

- GitHub Actions Android arm64 Vulkan job succeeds.
- Downloaded Android artifact runs in native Termux.
- `llama-bench --list-devices` reports `int dot: 1` on `Vulkan0`.
- Bonsai `Q2_0` smoke benchmark completes without the old descriptor-set crash.

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
