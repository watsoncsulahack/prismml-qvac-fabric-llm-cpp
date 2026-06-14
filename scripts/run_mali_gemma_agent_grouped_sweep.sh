#!/usr/bin/env bash
set -u

BIN_DIR="${BIN_DIR:-/data/data/com.termux/files/home/android-arm64-vulkan}"
OUT_DIR="${OUT_DIR:-/data/data/com.termux/files/home/benchmarks/mali-g715-gemma-agent-grouped-sweep-$(date -u +%Y%m%dT%H%M%SZ)}"

THREADS="${THREADS:-2}"
NGL="${NGL:-99}"
DEVICE="${DEVICE:-Vulkan0}"
FLASH_ATTN="${FLASH_ATTN:-0}"
REPEAT="${REPEAT:-1}"
PHASE_TIMEOUT="${PHASE_TIMEOUT:-1800}"

MODEL_SET="${MODEL_SET:-primary_xl:/data/data/com.termux/files/home/models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf q4km:/data/data/com.termux/files/home/qvac/gemma-4-E2B-it-Q4_K_M.gguf bonsai1p7b:/data/data/com.termux/files/home/models/Ternary-Bonsai-1.7B-Q2_0.gguf}"

mkdir -p "$OUT_DIR/raw"
export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

{
  printf 'date_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'bin_dir=%s\n' "$BIN_DIR"
  printf 'out_dir=%s\n' "$OUT_DIR"
  printf 'threads=%s\n' "$THREADS"
  printf 'ngl=%s\n' "$NGL"
  printf 'device=%s\n' "$DEVICE"
  printf 'flash_attn=%s\n' "$FLASH_ATTN"
  printf 'repeat=%s\n' "$REPEAT"
  printf 'phase_timeout=%s\n' "$PHASE_TIMEOUT"
  printf 'model_set=%s\n' "$MODEL_SET"
  printf 'uname=%s\n' "$(uname -a)"
  command -v getprop >/dev/null 2>&1 && {
    printf 'ro.product.model=%s\n' "$(getprop ro.product.model)"
    printf 'ro.board.platform=%s\n' "$(getprop ro.board.platform)"
    printf 'ro.hardware.vulkan=%s\n' "$(getprop ro.hardware.vulkan)"
  }
  command -v termux-battery-status >/dev/null 2>&1 && {
    printf 'battery_start=%s\n' "$(termux-battery-status | tr '\n' ' ')"
  }
} > "$OUT_DIR/env.txt"

"$BIN_DIR/llama-bench" --list-devices > "$OUT_DIR/list-devices.log" 2>&1
printf '%s\n' "$?" > "$OUT_DIR/list-devices.exit"

summary="$OUT_DIR/summary.tsv"
printf 'phase\tmodel_label\tmodel\trc\tseconds\toutput\tcommand\n' > "$summary"

run_phase() {
  phase="$1"
  label="$2"
  model="$3"
  shift 3

  safe_label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9_' '_')"
  safe_phase="$(printf '%s' "$phase" | tr -c 'A-Za-z0-9_' '_')"
  out="$OUT_DIR/raw/${safe_phase}_${safe_label}.json"
  log="$OUT_DIR/raw/${safe_phase}_${safe_label}.log"

  printf '[%s] phase=%s model=%s\n' "$(date -u +%H:%M:%S)" "$phase" "$label"
  start="$(date +%s)"

  if [ ! -f "$model" ]; then
    printf 'missing model: %s\n' "$model" > "$log"
    rc=66
  else
    timeout "$PHASE_TIMEOUT" "$BIN_DIR/llama-bench" \
      -m "$model" \
      -dev "$DEVICE" \
      -ngl "$NGL" \
      -t "$THREADS" \
      -r "$REPEAT" \
      -fa "$FLASH_ATTN" \
      --no-warmup \
      "$@" \
      -o json > "$out" 2> "$log"
    rc="$?"
  fi

  end="$(date +%s)"
  seconds="$((end - start))"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t' "$phase" "$label" "$model" "$rc" "$seconds" "$out" >> "$summary"
  printf '%q ' "$BIN_DIR/llama-bench" -m "$model" -dev "$DEVICE" -ngl "$NGL" -t "$THREADS" -r "$REPEAT" -fa "$FLASH_ATTN" --no-warmup "$@" -o json >> "$summary"
  printf '\n' >> "$summary"
  printf '[%s] phase=%s model=%s rc=%s seconds=%s output=%s\n' "$(date -u +%H:%M:%S)" "$phase" "$label" "$rc" "$seconds" "$out"
}

for item in $MODEL_SET; do
  label="${item%%:*}"
  model="${item#*:}"

  run_phase baseline "$label" "$model" \
    -p 512 -n 32 -d 0 -b 512 -ub 64 -ctk f16 -ctv f16

  run_phase context_depth "$label" "$model" \
    -p 0 -n 128 -d 0,2048,4096,6144,8192 -b 512 -ub 64 -ctk f16 -ctv f16

  run_phase batch "$label" "$model" \
    -p 512 -n 32 -d 0 -b 512,768,1024 -ub 64 -ctk f16 -ctv f16

  run_phase microbatch "$label" "$model" \
    -p 512 -n 32 -d 0 -b 512 -ub 48,64,80,96 -ctk f16 -ctv f16

  run_phase kv_f16 "$label" "$model" \
    -p 0 -n 128 -d 4096 -b 512 -ub 64 -ctk f16 -ctv f16

  run_phase kv_q8 "$label" "$model" \
    -p 0 -n 128 -d 4096 -b 512 -ub 64 -ctk q8_0 -ctv q8_0

  run_phase kv_q8k_f16v "$label" "$model" \
    -p 0 -n 128 -d 4096 -b 512 -ub 64 -ctk q8_0 -ctv f16
done

command -v termux-battery-status >/dev/null 2>&1 && {
  termux-battery-status > "$OUT_DIR/battery-end.json" 2>/dev/null || true
}

printf 'DONE %s\n' "$OUT_DIR" > "$OUT_DIR/DONE"
printf '%s\n' "$OUT_DIR"
