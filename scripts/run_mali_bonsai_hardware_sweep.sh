#!/usr/bin/env bash
set -u

BIN_DIR="${BIN_DIR:-/data/data/com.termux/files/home/android-arm64-vulkan}"
MODEL="${MODEL:-/data/data/com.termux/files/home/Ternary-Bonsai-1.7B-Q2_0.gguf}"
OUT_DIR="${OUT_DIR:-/data/data/com.termux/files/home/benchmarks/mali-bonsai-hardware-spread-$(date -u +%Y%m%dT%H%M%SZ)}"

PROMPT_TOKENS="${PROMPT_TOKENS:-128}"
GEN_TOKENS="${GEN_TOKENS:-128}"
REPEAT="${REPEAT:-2}"
BATCH_SIZE="${BATCH_SIZE:-256}"
UBATCH_SIZE="${UBATCH_SIZE:-64}"
BATCH_UBATCH_SPREAD="${BATCH_UBATCH_SPREAD:-}"
FLASH_ATTN="${FLASH_ATTN:-0}"
PROMPT_CHARS="${PROMPT_CHARS:-0}"
MODEL_TOKEN_BYTES="${MODEL_TOKEN_BYTES:-0}"
SPREAD_THREADS="${SPREAD_THREADS:-2}"
SPREAD_NGL="${SPREAD_NGL:-99}"

THREADS_LIST="${THREADS_LIST:-1 2 4 6 8}"
NGL_LIST="${NGL_LIST:-0 1 8 16 99}"

mkdir -p "$OUT_DIR/raw"

export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

{
  printf 'date_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'bin_dir=%s\n' "$BIN_DIR"
  printf 'model=%s\n' "$MODEL"
  printf 'out_dir=%s\n' "$OUT_DIR"
  printf 'prompt_tokens=%s\n' "$PROMPT_TOKENS"
  printf 'gen_tokens=%s\n' "$GEN_TOKENS"
  printf 'repeat=%s\n' "$REPEAT"
  printf 'batch_size=%s\n' "$BATCH_SIZE"
  printf 'ubatch_size=%s\n' "$UBATCH_SIZE"
  printf 'batch_ubatch_spread=%s\n' "$BATCH_UBATCH_SPREAD"
  printf 'flash_attn=%s\n' "$FLASH_ATTN"
  printf 'prompt_chars=%s\n' "$PROMPT_CHARS"
  printf 'model_token_bytes=%s\n' "$MODEL_TOKEN_BYTES"
  printf 'spread_threads=%s\n' "$SPREAD_THREADS"
  printf 'spread_ngl=%s\n' "$SPREAD_NGL"
  printf 'threads_list=%s\n' "$THREADS_LIST"
  printf 'ngl_list=%s\n' "$NGL_LIST"
  printf 'uname=%s\n' "$(uname -a)"
  command -v getprop >/dev/null 2>&1 && {
    printf 'ro.product.model=%s\n' "$(getprop ro.product.model)"
    printf 'ro.board.platform=%s\n' "$(getprop ro.board.platform)"
    printf 'ro.hardware.vulkan=%s\n' "$(getprop ro.hardware.vulkan)"
  }
} > "$OUT_DIR/env.txt"

"$BIN_DIR/llama-bench" --list-devices > "$OUT_DIR/list-devices.log" 2>&1
printf '%s\n' "$?" > "$OUT_DIR/list-devices.exit"

summary="$OUT_DIR/summary.tsv"
printf 'phase\tthreads\tthreads_batch\tngl\tdevice\tprompt_tokens\tgen_tokens\ttotal_tokens\tprompt_chars\tmodel_token_bytes\trepeat\tbatch\tubatch\tflash_attn\trc\tseconds\toutput\n' > "$summary"

run_one() {
  phase="$1"
  threads="$2"
  threads_batch="$3"
  ngl="$4"
  dev="$5"
  prompt="$6"
  gen="$7"
  repeat="$8"
  batch="$9"
  ubatch="${10}"
  fa="${11}"
  prompt_chars="${12}"
  model_token_bytes="${13}"
  total_tokens="$((prompt + gen))"

  safe_dev="$(printf '%s' "$dev" | tr -c 'A-Za-z0-9_' '_')"
  name="${phase}_t${threads}_tb${threads_batch}_ngl${ngl}_${safe_dev}_p${prompt}_n${gen}_b${batch}_ub${ubatch}_fa${fa}"
  out="$OUT_DIR/raw/$name.json"
  log="$OUT_DIR/raw/$name.log"
  start="$(date +%s)"

  if [ "$dev" = "none" ]; then
    "$BIN_DIR/llama-bench" \
      -m "$MODEL" \
      -dev none \
      -ngl "$ngl" \
      -t "$threads" \
      -p "$prompt" \
      -n "$gen" \
      -r "$repeat" \
      -b "$batch" \
      -ub "$ubatch" \
      -fa "$fa" \
      --no-warmup \
      -o json > "$out" 2> "$log"
  else
    "$BIN_DIR/llama-bench" \
      -m "$MODEL" \
      -dev "$dev" \
      -ngl "$ngl" \
      -t "$threads" \
      -p "$prompt" \
      -n "$gen" \
      -r "$repeat" \
      -b "$batch" \
      -ub "$ubatch" \
      -fa "$fa" \
      --no-warmup \
      -o json > "$out" 2> "$log"
  fi
  rc="$?"
  end="$(date +%s)"
  seconds="$((end - start))"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$phase" "$threads" "$threads_batch" "$ngl" "$dev" "$prompt" "$gen" "$total_tokens" "$prompt_chars" "$model_token_bytes" "$repeat" "$batch" "$ubatch" "$fa" "$rc" "$seconds" "$out" >> "$summary"
}

if [ -n "$BATCH_UBATCH_SPREAD" ]; then
  for pair in $BATCH_UBATCH_SPREAD; do
    batch="${pair%%:*}"
    ubatch="${pair#*:}"
    run_one spread "$SPREAD_THREADS" "$SPREAD_THREADS" "$SPREAD_NGL" Vulkan0 "$PROMPT_TOKENS" "$GEN_TOKENS" "$REPEAT" "$batch" "$ubatch" "$FLASH_ATTN" "$PROMPT_CHARS" "$MODEL_TOKEN_BYTES"
  done
else
  for ngl in $NGL_LIST; do
    for threads in $THREADS_LIST; do
      if [ "$ngl" = "0" ]; then
        dev="none"
      else
        dev="Vulkan0"
      fi
      run_one decode "$threads" "$threads" "$ngl" "$dev" "$PROMPT_TOKENS" "$GEN_TOKENS" "$REPEAT" "$BATCH_SIZE" "$UBATCH_SIZE" "$FLASH_ATTN" "$PROMPT_CHARS" "$MODEL_TOKEN_BYTES"
    done
  done
fi

printf 'DONE %s\n' "$OUT_DIR" > "$OUT_DIR/DONE"
