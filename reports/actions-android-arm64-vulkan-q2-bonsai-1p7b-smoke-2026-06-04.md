# Actions Android Q2_0 Bonsai 1.7B Smoke

Date: 2026-06-04 UTC

Artifact source:

- Repository: `watsoncsulahack/prismml-qvac-fabric-llm-cpp`
- Build commit: `e2a636e`
- Android artifact: `android-arm64-vulkan-binaries`
- Local binary directory:
  `/data/data/com.termux/files/home/openclaw-binaries/prismml-qvac-actions-e2a636e`

Model:

- Hugging Face repo: `prism-ml/Ternary-Bonsai-1.7B-gguf`
- File: `Ternary-Bonsai-1.7B-Q2_0.gguf`
- Local path:
  `/root/.openclaw/workspace/models/prismml/Ternary-Bonsai-1.7B-Q2_0.gguf`
- SHA256:
  `d97d94eb564590c9f0300e54d3f87bbbb25a78693d0ade9f6e177973dcb8228a`

Device:

```text
Google Pixel 9 Pro Fold
GPU: Mali-G715
Runtime: native Termux via com.termux.RUN_COMMAND
Vulkan device: Vulkan0
```

Runtime capability check:

```text
Mali-G715 | fp16: 1 | bf16: 0 | warp size: 16 | shared memory: 32768 | int dot: 1 | matrix cores: KHR_coopmat
```

Command shape:

```sh
./llama-bench \
  -m /root/.openclaw/workspace/models/prismml/Ternary-Bonsai-1.7B-Q2_0.gguf \
  -p 64 -n 64 -r 1 \
  -dev Vulkan0 -ngl 99
```

Result:

| Model | Runtime | Build / commit | Device path | int dot | pp tok/s | tg tok/s | rc | Notes |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| Bonsai 1.7B `Q2_0` | PrismML Actions Android artifact | `e2a636e` | Vulkan0 | 1 | 47.70 | 17.92 | 0 | Full offload, no descriptor-set crash |

Raw benchmark output:

```text
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Mali-G715 (Mali-G715) | uma: 1 | fp16: 1 | bf16: 0 | warp size: 16 | shared memory: 32768 | int dot: 1 | matrix cores: KHR_coopmat
| model                          |       size |     params | backend    | ngl | dev          |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | ------------ | --------------: | -------------------: |
| qwen3 1.7B Q2_0                | 436.16 MiB |     1.72 B | Vulkan     |  99 | Vulkan0      |            pp64 |         47.70 +/- 0.00 |
| qwen3 1.7B Q2_0                | 436.16 MiB |     1.72 B | Vulkan     |  99 | Vulkan0      |            tg64 |         17.92 +/- 0.00 |

build: e2a636e (1)
rc:0
```

This fills the smaller-model benchmark slot Allan requested. PrismML does not
currently have a local 2B Bonsai GGUF in this workspace; the closest published
smaller PrismML Bonsai GGUF found during this run was the 1.7B `Q2_0` model.
