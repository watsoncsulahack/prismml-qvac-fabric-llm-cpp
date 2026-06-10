# Android arm64 Vulkan int-dot benchmark - 2026-06-02

## Summary

GitHub Actions Android arm64 Vulkan artifacts now build with Vulkan integer-dot
shader support enabled and report `int dot: 1` at runtime on a Mali-G715
Android test device.

- CI run: https://github.com/watsoncsulahack/prismml-qvac-fabric-llm-cpp/actions/runs/26809874917
- Commit: `e2a636e` (`Copy full Vulkan SDK include tree for Android`)
- Diff from public cleanup baseline: https://github.com/watsoncsulahack/prismml-qvac-fabric-llm-cpp/compare/6681d0c...e2a636e
- Android artifact: `android-arm64-vulkan-binaries`
- Artifact zip: `android-arm64-vulkan-binaries.artifact.zip`
- Inner binary zip SHA256: `b41699c0a70b0352b3d8785086ccbf5194f219b3ab4dc38d18266ac6f186c9c7`
- Binary directory: extracted `android-arm64-vulkan-binaries` artifact

The previous green Actions artifact from `133a853` still reported `int dot: 0`
on device. The fix was to use LunarG Vulkan SDK `1.4.350.0` for the Android
shader compiler and headers, with a CI preflight that compiles
`integer_dot.comp` before CMake configure.

## Runtime Check

Command:

```bash
./llama-bench --list-devices
```

Output:

```text
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Mali-G715 (Mali-G715) | uma: 1 | fp16: 1 | bf16: 0 | warp size: 16 | shared memory: 32768 | int dot: 1 | matrix cores: KHR_coopmat
Available devices:
  Vulkan0: Mali-G715 (15455 MiB, 15455 MiB free)
rc=0
```

## Benchmarks

Command shape:

```bash
./llama-bench -m <model.gguf> -p 64 -n 64 -r 1 -dev Vulkan0 -ngl 99
```

| Model | Runtime | Build / commit | Backend | int dot | pp64 tok/s | tg64 tok/s | rc |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| Bonsai 4B `Q2_0` | PrismML Actions Android artifact | `e2a636e` | Vulkan0 | 1 | 18.36 | 7.70 | 0 |
| Bonsai 8B `Q2_0` | PrismML Actions Android artifact | `e2a636e` | Vulkan0 | 1 | 9.52 | 4.54 | 0 |

Raw outputs were captured from the extracted Android artifact directory.
