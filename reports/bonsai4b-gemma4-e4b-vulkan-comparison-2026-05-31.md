# Bonsai 4B vs Gemma 4 E4B Android Vulkan notes

Date: 2026-05-31

## Context

Follow-up to the Android arm64 Vulkan Actions build. The main questions were:

- why `int dot` differs between the native Termux PrismML build and the GitHub Actions Android artifact;
- whether Bonsai 4B is faster than Bonsai 8B;
- how Bonsai 4B compares with a roughly similar Gemma 4 edge model;
- what "unpack", "dequant", "matmul", and "synchronization" mean in the GPU path.

## Models downloaded

- Bonsai 4B: `Ternary-Bonsai-4B-Q2_0.gguf`
  - Source: `https://huggingface.co/prism-ml/Ternary-Bonsai-4B-gguf`
  - Local path: `/root/.openclaw/workspace/models/prismml/Ternary-Bonsai-4B-Q2_0.gguf`
  - Size reported by `llama-bench`: `1019.50 MiB`
  - Params reported by `llama-bench`: `4.02 B`
- Gemma 4 E4B Q4_K_M:
  - Source: `https://huggingface.co/mradermacher/gemma-4-E4B-GGUF`
  - Local path: `/data/data/com.termux/files/home/qvac/gemma-4-E4B.Q4_K_M.gguf`
  - Size reported by `llama-bench`: `4.95 GiB`
  - Params reported by `llama-bench`: `7.52 B`

Note: Gemma 4 E4B is not actually a 4.0B parameter model in this GGUF; it reports 7.52B params. That makes the comparison useful but not perfectly parameter-matched.

## Benchmark results

All tests used native Termux `RUN_COMMAND` outside PRoot on `Vulkan0: Mali-G715`, with:

```text
-p 64 -n 64 -r 1 -dev Vulkan0 -ngl 99
```

| Model | Runtime binary | Build | int dot | pp64 tok/s | tg64 tok/s | rc |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Bonsai 4B Q2_0 | PrismML Actions Android artifact | `efea4ca` | 0 | 20.50 | 8.61 | 0 |
| Bonsai 4B Q2_0 | PrismML native Termux build | `747eb36` | 1 | 20.53 | 8.93 | 0 |
| Bonsai 8B Q2_0 | PrismML Actions Android artifact | `efea4ca` | 0 | 10.67 | 5.11 | 0 |
| Gemma 4 E4B Q4_K_M | QVAC native Termux build | `6f541c5` | 1 | 2.55 | 4.69 | 0 |
| Gemma 4 E2B Q4_K_M | QVAC native Termux build | `6f541c5` | 1 | 5.08 | 8.08 | 0 |

## `int dot` finding

The `int dot` value is printed by `ggml-vulkan.cpp` after runtime Vulkan feature discovery. In this fork, it requires all of the following:

- the shader build has `GGML_VULKAN_INTEGER_DOT_GLSLC_SUPPORT`;
- the runtime device advertises `VK_KHR_shader_integer_dot_product`;
- `integerDotProduct4x8BitPackedSignedAccelerated` is true;
- `shaderIntegerDotProduct` is true;
- `GGML_VK_DISABLE_INTEGER_DOT_PRODUCT` is not set.

Source pointers:

- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: extension scan around `VK_KHR_shader_integer_dot_product`
- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: final runtime check against `integerDotProduct4x8BitPackedSignedAccelerated` and `shaderIntegerDotProduct`
- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: `int dot: %d` debug print

Observed discrepancy:

- Actions Android artifact: `int dot: 0`
- Native Termux PrismML build: `int dot: 1`
- QVAC native Termux build: `int dot: 1`

Most likely cause: the Actions artifact was cross-built with the Android NDK plus manually copied Vulkan/SPIR-V headers, while the native Termux builds used the Termux Vulkan toolchain/runtime environment. The same physical GPU can therefore expose the extension, but the binary may not compile/query/enable the integer-dot path in the same way.

Important: Bonsai 4B `ngl=99` decode changed only from `8.61` to `8.93 tok/s` between `int dot: 0` and `int dot: 1`, so integer dot is not the main Bonsai performance explanation in this test.

## Q2_0 vs TQ2_0 kernel-layout notes

PrismML Bonsai Q2_0:

- block size: 128 weights;
- block layout: `fp16 d` then `qs[32]`;
- source layout in `ggml-common.h`: `block_q2_0`;
- Vulkan layout in `types.glsl`: `block_q2_0`;
- dequant extracts 2-bit codes from `qs[iqs / 4]`, shifts by `(iqs % 4) * 2`, subtracts 1, then multiplies by scale `d`.

QVAC TQ2_0:

- block size: 256 weights;
- block layout: `qs[64]` then `fp16 d`;
- source layout in `ggml-common.h`: `block_tq2_0`;
- Vulkan layout in `types.glsl`: `block_tq2_0`;
- dequant uses a different index pattern: `upper = iqs / 128`, `byte = (upper * 32) + (iqs % 32)`, `shift = ((iqs % 128) / 32) * 2`.

These layouts are not byte-compatible. A QVAC TQ2_0 kernel cannot safely read PrismML Bonsai Q2_0 blocks without either a real repacking converter or PrismML Q2_0 support inside QVAC.

## Practical interpretation

Bonsai 4B looks much better than Bonsai 8B on the patched PrismML Vulkan path:

- Bonsai 8B: `tg64 5.11 tok/s`
- Bonsai 4B: `tg64 8.61-8.93 tok/s`

That makes the Bonsai result less mysterious: the 8B model was slow because it is still a large model and its Q2_0 path is not an especially magical 1-bit GPU path. The 4B model is materially faster, but not because the GPU is doing pure ternary math for free. The runtime still has to unpack packed codes, apply scales, multiply against activations, accumulate, and coordinate GPU workgroups.

