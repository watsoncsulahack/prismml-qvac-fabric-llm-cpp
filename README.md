# prismml-qvac-fabric-llm-cpp

Private experimental fork for making PrismML Ternary-Bonsai GGUF models run
reliably with Vulkan acceleration on Android.

This fork started from the
[PrismML llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp), because that
tree already knows how to load PrismML Bonsai `Q1_0` / `Q2_0` tensors. The
Android/Vulkan build and runtime work is informed by
[Tether/QVAC Fabric LLM.cpp](https://github.com/tetherto/qvac-fabric-llm.cpp),
which has a healthier native Termux Vulkan path on the same device.

The upstream llama.cpp README has intentionally been removed from this fork's
front page so the repository reflects the current experiment rather than the
general upstream project.

## Current Status

The patched PrismML Vulkan path now runs Bonsai models on Android without the
previous descriptor-set assertion:

```text
GGML_ASSERT(ctx->descriptor_set_idx < ctx->descriptor_sets.size()) failed
```

GitHub Actions now produces an Android arm64 Vulkan artifact containing:

- `llama-bench`
- `llama-cli`
- `libggml-vulkan.so`
- required Android shared libraries such as `libc++_shared.so`

The artifact has been copied into native Termux and tested outside PRoot.

## Test Device

Benchmarks so far were run on Allan's:

```text
Google Pixel 9 Pro Fold
GPU: Mali-G715
Runtime: native Termux via com.termux.RUN_COMMAND
Vulkan device: Vulkan0
```

Observed Vulkan capability lines vary by binary:

```text
Actions PrismML Android artifact e2a636e+:
Mali-G715 | fp16: 1 | int dot: 1 | matrix cores: KHR_coopmat

Native Termux PrismML build:
Mali-G715 | fp16: 1 | int dot: 1 | matrix cores: KHR_coopmat

Native Termux QVAC build:
Mali-G715 | fp16: 1 | int dot: 1 | matrix cores: KHR_coopmat
```

Older Actions artifacts built before `e2a636e` reported `int dot: 0` because
Ubuntu's packaged shader tools did not support `GL_EXT_integer_dot_product`
during Android cross-build configuration. The Actions workflow now uses the
LunarG Vulkan SDK shader compiler and fails fast if the integer-dot feature test
does not compile.

## Benchmark Table

Unless noted otherwise, benchmarks used:

```text
-p 64 -n 64 -r 1 -dev Vulkan0 -ngl 99
```

| Model | Runtime | Build / commit | Device path | int dot | pp tok/s | tg tok/s | rc | Notes |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| Bonsai 8B `Q2_0` | PrismML Actions Android artifact | `e2a636e` | Vulkan0 | 1 | 9.52 | 4.54 | 0 | Actions artifact built with LunarG Vulkan SDK `1.4.350.0` |
| Bonsai 8B `Q2_0` | PrismML Actions Android artifact | `efea4ca` | Vulkan0 | 0 | 10.67 | 5.11 | 0 | Full offload smoke after descriptor-set fix |
| Bonsai 8B `Q2_0` | PrismML native Termux build | `747eb36` | Vulkan0 | 1 | 2.90 | 5.11 | 0 | Earlier short `p16/n16` full-offload smoke |
| Bonsai 8B `Q2_0` | PrismML native Termux build | `747eb36` | CPU | n/a | 1.03 | 1.41 | 0 | CPU baseline, `-dev none -ngl 0` |
| Bonsai 4B `Q2_0` | PrismML Actions Android artifact | `e2a636e` | Vulkan0 | 1 | 18.36 | 7.70 | 0 | Actions artifact built with LunarG Vulkan SDK `1.4.350.0` |
| Bonsai 4B `Q2_0` | PrismML Actions Android artifact | `efea4ca` | Vulkan0 | 0 | 20.50 | 8.61 | 0 | Downloaded from `prism-ml/Ternary-Bonsai-4B-gguf` |
| Bonsai 4B `Q2_0` | PrismML native Termux build | `747eb36` | Vulkan0 | 1 | 20.53 | 8.93 | 0 | Same model/device, native Termux binary |
| Gemma 4 E2B `Q4_K_M` | QVAC native Termux build | `6f541c5` | CPU | n/a | 14.19 | 3.22 | 0 | Prior QVAC CPU baseline |
| Gemma 4 E2B `Q4_K_M` | QVAC native Termux build | `6f541c5` | Vulkan0 | 1 | 5.08 | 8.08 | 0 | Stable QVAC Android Vulkan path |
| Gemma 4 E4B `Q4_K_M` | QVAC native Termux build | `6f541c5` | Vulkan0 | 1 | 2.55 | 4.69 | 0 | GGUF reports `7.52B` params / `4.95 GiB`, so not truly 4B-matched |

Detailed reports:

- [Android arm64 Vulkan int-dot benchmark](reports/actions-android-arm64-vulkan-intdot-bench-2026-06-02.md)
- [Android arm64 Vulkan smoke test](reports/actions-android-arm64-vulkan-smoke-2026-05-31.md)
- [Bonsai 4B vs Gemma 4 E4B Vulkan comparison](reports/bonsai4b-gemma4-e4b-vulkan-comparison-2026-05-31.md)

## Compatibility Notes

Do not re-ID Bonsai from PrismML `Q2_0` to QVAC `TQ2_0`. They are different
on-disk formats:

| Format | Raw type observed | Weights per block | Bytes per block | Layout |
| --- | ---: | ---: | ---: | --- |
| PrismML Bonsai `Q2_0` | `42` | 128 | 34 | `fp16 d`, then `qs[32]` |
| QVAC `TQ2_0` | `35` | 256 | 66 | `qs[64]`, then `fp16 d` |

QVAC's current type `42` means `TBQ3_0`, not PrismML Bonsai `Q2_0`. A simple
type-ID remap would make QVAC read the wrong bytes. Correct support requires
either:

- native PrismML `Q2_0` support inside QVAC; or
- a real converter that repacks PrismML `Q2_0` tensors into a QVAC-compatible
  tensor layout.

## Project Notes

Active follow-up tasks live in [docs/todo.md](docs/todo.md).

## Build Notes

Linux/Vulkan CI build:

```sh
cmake -B build -G Ninja -DGGML_VULKAN=ON -DLLAMA_BUILD_TESTS=OFF
cmake --build build --target llama-bench llama-cli -j "$(nproc)"
```

Android arm64 Vulkan CI build:

```sh
cmake -B build-android-arm64-vulkan -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-31 \
  -DANDROID_STL=c++_shared \
  -DGGML_NATIVE=OFF \
  -DGGML_CPU_ARM_ARCH=armv8.5-a+fp16+i8mm \
  -DGGML_VULKAN=ON \
  -DGGML_OPENMP=OFF \
  -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF

cmake --build build-android-arm64-vulkan --target llama-bench llama-cli -j "$(nproc)"
```

Native Termux Bonsai full-offload smoke:

```sh
./llama-bench \
  -m /path/to/Ternary-Bonsai-8B-Q2_0.gguf \
  -p 64 -n 64 -r 1 \
  -dev Vulkan0 -ngl 99
```
