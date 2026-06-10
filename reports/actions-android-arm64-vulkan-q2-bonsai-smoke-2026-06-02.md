# Actions Android Q2_0 Bonsai Smoke

Date: 2026-06-02 UTC

Artifact source:

- Repository: `watsoncsulahack/prismml-qvac-fabric-llm-cpp`
- Build commit: `e2a636e`
- Actions run: <https://github.com/watsoncsulahack/prismml-qvac-fabric-llm-cpp/actions/runs/26809874917>
- Binary directory: extracted `android-arm64-vulkan-binaries` artifact

Reference runtime:

```text
GPU: Mali-G715
Runtime: native Termux
Vulkan device: Vulkan0
```

Runtime capability check:

```text
Mali-G715 | fp16: 1 | bf16: 0 | warp size: 16 | shared memory: 32768 | int dot: 1 | matrix cores: KHR_coopmat
```

Command shape:

```sh
./llama-bench \
  -m /path/to/Ternary-Bonsai-4B-Q2_0.gguf \
  -p 64 -n 64 -r 1 \
  -dev Vulkan0 -ngl 99
```

The 8B smoke used the same arguments with
`Ternary-Bonsai-8B-Q2_0.gguf`.

Results:

| Model | Runtime | Build / commit | Backend | int dot | pp tok/s | tg tok/s | Notes |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| Bonsai 4B `Q2_0` | PrismML Actions Android artifact | `e2a636e` | Vulkan0 | 1 | 20.30 | 7.76 | Full offload, no descriptor-set crash |
| Bonsai 8B `Q2_0` | PrismML Actions Android artifact | `e2a636e` | Vulkan0 | 1 | 10.70 | 4.72 | Full offload, no descriptor-set crash |

This completes the TODO #1 acceptance check that the downloaded Android
artifact runs in native Termux, reports `int dot: 1`, and completes Bonsai
`Q2_0` smoke benchmarks without the prior Vulkan descriptor-set assertion.
