# Actions Android arm64 Vulkan Smoke Test - 2026-05-31

## Repository State

- Repository: `watsoncsulahack/prismml-qvac-fabric-llm-cpp`
- Visibility observed through GitHub API: private
- Base smoke patch commit: `dead4c5`
- Android workflow commit: `efea4ca`
- Successful workflow run: `26706235299`
- Android artifact: `android-arm64-vulkan-binaries`

## What Changed

The original workflow only produced Ubuntu x86-64 Vulkan binaries. That proved
the patched source compiled, but it was not useful for native Termux testing on
the Android aarch64 device.

The workflow now also builds Android arm64 Vulkan tools with the Android NDK:

- `llama-bench`
- `llama-cli`
- required shared libraries, including `libggml-vulkan.so` and
  `libc++_shared.so`

The Android job needed host-side Khronos headers copied into the NDK sysroot:

- `vulkan/vulkan.hpp` from `libvulkan-dev`
- `spirv/unified1/spirv.hpp` from `spirv-headers`

## Native Termux Test

Artifact extracted to:

```text
/data/data/com.termux/files/home/openclaw-binaries/prismml-qvac-actions-efea4ca
```

The binary is an Android aarch64 executable:

```text
llama-bench: ELF 64-bit LSB pie executable, ARM aarch64, interpreter /system/bin/linker64, for Android 31
llama-cli:   ELF 64-bit LSB pie executable, ARM aarch64, interpreter /system/bin/linker64, for Android 31
```

Native Termux execution used `com.termux.RUN_COMMAND`, confirming it ran outside
the PRoot environment as Android user `u0_a335`.

## Device Detection

```text
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Mali-G715 (Mali-G715) | uma: 1 | fp16: 1 | bf16: 0 | warp size: 16 | shared memory: 32768 | int dot: 0 | matrix cores: KHR_coopmat
Available devices:
  Vulkan0: Mali-G715 (15455 MiB, 15455 MiB free)
```

## Bonsai Smoke Results

Model:

```text
/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/.openclaw/workspace/models/prismml/Ternary-Bonsai-8B-Q2_0.gguf
```

Short smoke test, `-p 16 -n 16 -r 1`:

| ngl | pp16 tok/s | tg16 tok/s | rc |
| --: | ---------: | ---------: | -: |
| 1   | 2.06      | 0.20       | 0  |
| 8   | 1.87      | 0.22       | 0  |
| 99  | 2.73      | 5.11       | 0  |

Fuller smoke test, `-p 64 -n 64 -r 1 -dev Vulkan0 -ngl 99`:

| ngl | pp64 tok/s | tg64 tok/s | rc |
| --: | ---------: | ---------: | -: |
| 99  | 10.67     | 5.11       | 0  |

## Read

The GitHub Actions Android artifact is usable for native Termux testing and the
descriptor-set crash remains fixed in this smoke path. The important next
technical question is performance quality: the Android Actions build reports
`int dot: 0`, while the earlier native Termux build reported `int dot: 1`; the
decode speed is still around the previous full-offload result, but prompt
processing differs enough that Android NDK flags and runtime feature detection
deserve a closer pass before treating this as the final build recipe.
