# Android arm64 Vulkan server bundle - 2026-06-08

## Summary

Built and released a Bonsai-compatible Android arm64 Vulkan command-line bundle
that includes `llama-server` in addition to `llama-cli` and `llama-bench`.

- Repository: `watsoncsulahack/prismml-qvac-fabric-llm-cpp`
- Build commit: `12b7c38` (`Build Android Vulkan llama-server artifact`)
- Actions run:
  <https://github.com/watsoncsulahack/prismml-qvac-fabric-llm-cpp/actions/runs/27139134484>
- Release:
  <https://github.com/watsoncsulahack/prismml-qvac-fabric-llm-cpp/releases/tag/android-vulkan-server-12b7c38>
- Android asset:
  `prismml-qvac-fabric-llm-cpp-12b7c38-android-arm64-vulkan-server-binaries.zip`
- SHA256:
  `72a27186bc5e7e243b924876f8d1251ac605c2f5cd20800779b4174501548278`

This is not an APK. It is a Termux/Android CLI bundle.

## What Changed

The `Vulkan smoke build` GitHub Actions workflow now builds and packages
`llama-server` for both Linux Vulkan smoke artifacts and Android arm64 Vulkan
artifacts.

The Android zip contains:

```text
android-arm64-vulkan/llama-server
android-arm64-vulkan/llama-cli
android-arm64-vulkan/llama-bench
android-arm64-vulkan/libggml-vulkan.so
android-arm64-vulkan/libggml-cpu.so
android-arm64-vulkan/libggml-base.so
android-arm64-vulkan/libggml.so
android-arm64-vulkan/libllama.so
android-arm64-vulkan/libllama-common.so
android-arm64-vulkan/libmtmd.so
android-arm64-vulkan/libc++_shared.so
```

## Verification

Local Android/Bionic executable check:

```text
version: 1 (12b7c38)
built with Clang 18.0.3 for Android aarch64
```

Bonsai 1.7B model:

- File: `Ternary-Bonsai-1.7B-Q2_0.gguf`
- Prior broken server builds failed immediately with invalid GGUF tensor type or
  tensor offset errors.
- New `12b7c38` `llama-server` loads the model and reaches HTTP serving.

Full Vulkan offload server smoke:

```text
llama_model_load_from_file_impl: using device Vulkan0 (Mali-G715)
load_tensors: offloaded 29/29 layers to GPU
load_tensors:      Vulkan0 model buffer size =   436.16 MiB
llama_kv_cache:    Vulkan0 KV buffer size =   112.00 MiB
sched_reserve:    Vulkan0 compute buffer size =   300.23 MiB
main: model loaded
main: server is listening on http://127.0.0.1:18081
```

HTTP completion smoke:

```text
POST /completion 127.0.0.1 200
tokens_predicted: 8
```

The tiny completion prompt was only a transport/server smoke test, not a quality
benchmark. It proves the new Android server binary can load Bonsai 1.7B, use
Mali-G715 Vulkan full offload, and serve an HTTP completion request.
