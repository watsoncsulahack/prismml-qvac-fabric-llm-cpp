#!/usr/bin/env bash
set -euo pipefail

out=
input=
target_env="vulkan1.2"
depfile=
args=(-V -S comp)
tmp_out=

cleanup() {
  if [[ -n "$tmp_out" && -f "$tmp_out" ]]; then
    rm -f "$tmp_out"
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

if [[ "$out" == "-" ]]; then
  tmp_out="$(mktemp)"
  glslangValidator "${args[@]}" --target-env "$target_env" "$input" -o "$tmp_out" >/dev/null
  cat "$tmp_out"
else
  mkdir -p "$(dirname "$out")"
  glslangValidator "${args[@]}" --target-env "$target_env" "$input" -o "$out"
fi

if [[ -n "$depfile" ]]; then
  mkdir -p "$(dirname "$depfile")"
  printf '%s: %s\n' "$out" "$input" > "$depfile"
fi
