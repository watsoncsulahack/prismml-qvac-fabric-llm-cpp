#!/usr/bin/env bash
set -euo pipefail

out=
input=
target_env="vulkan1.2"
depfile=
args=(-V -S comp)
tmp_out=
tmp_input=

cleanup() {
  if [[ -n "$tmp_out" && -f "$tmp_out" ]]; then
    rm -f "$tmp_out"
  fi
  if [[ -n "$tmp_input" && -f "$tmp_input" ]]; then
    rm -f "$tmp_input"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    -fshader-stage=compute)
      shift
      ;;
    --target-env=*)
      target_env="${1#--target-env=}"
      shift
      ;;
    --target-env)
      target_env="$2"
      shift 2
      ;;
    -o)
      out="$2"
      shift 2
      ;;
    -O)
      shift
      ;;
    -MD)
      shift
      ;;
    -MF)
      depfile="$2"
      shift 2
      ;;
    -D*)
      args+=("$1")
      shift
      ;;
    *)
      input="$1"
      shift
      ;;
  esac
done

if [[ -z "$out" || -z "$input" ]]; then
  echo "usage: glslc-glslang-wrapper.sh [glslc-compatible args] shader.comp -o shader.spv" >&2
  exit 2
fi

if grep -q '^[[:space:]]*#include[[:space:]]' "$input"; then
  tmp_input="$(mktemp --suffix=.comp)"
  awk '
    /^[[:space:]]*#version[[:space:]]/ && !inserted {
      print
      print "#extension GL_GOOGLE_include_directive : require"
      inserted = 1
      next
    }
    { print }
  ' "$input" > "$tmp_input"
  args+=("-I$(dirname "$input")")
  input="$tmp_input"
fi

run_glslang() {
  local output

  if ! output=$(glslangValidator "${args[@]}" --target-env "$target_env" "$input" -o "$1" 2>&1); then
    printf '%s\n' "$output" >&2
    return 1
  fi
}

if [[ "$out" == "-" ]]; then
  tmp_out="$(mktemp)"
  run_glslang "$tmp_out"
  cat "$tmp_out"
else
  mkdir -p "$(dirname "$out")"
  run_glslang "$out"
fi

if [[ -n "$depfile" ]]; then
  mkdir -p "$(dirname "$depfile")"
  printf '%s: %s\n' "$out" "$input" > "$depfile"
fi
