#!/usr/bin/env bash
# speckit-guard: runs gremlins package by package under a memory cap and a time limit.
# Usage: mutation-go.sh <package>...
set -uo pipefail

mem="${SPECKIT_MUTATION_MEMORY:-4G}"
workers="${SPECKIT_MUTATION_WORKERS:-2}"
coefficient="${SPECKIT_MUTATION_TIMEOUT_COEFFICIENT:-10}"
budget="${SPECKIT_MUTATION_PACKAGE_TIMEOUT:-1800}"

(( $# > 0 )) || { echo "usage: mutation-go.sh <package>..." >&2; exit 2; }
command -v gremlins >/dev/null 2>&1 || { echo "speckit-guard: gremlins not installed, mutation testing not run" >&2; exit 3; }

to_kib() {
  local n="${1%[KkMmGg]}"
  case "$1" in
    *[Gg]) echo $(( n * 1024 * 1024 )) ;;
    *[Mm]) echo $(( n * 1024 )) ;;
    *[Kk]) echo "$n" ;;
    *) echo $(( n / 1024 )) ;;
  esac
}

capped=()
if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope -q -p MemoryMax=64M true >/dev/null 2>&1; then
  capped=(systemd-run --user --scope -q -p "MemoryMax=$mem" -p MemorySwapMax=0 -p OOMPolicy=continue -p "RuntimeMaxSec=$budget")
else
  echo "speckit-guard: systemd-run unavailable, each process is capped at $mem of address space" >&2
  ulimit -v "$(to_kib "$mem")" || { echo "speckit-guard: cannot cap memory, mutation testing not run" >&2; exit 3; }
  command -v timeout >/dev/null 2>&1 && capped=(timeout --kill-after=30 "$budget")
fi

status=0
for pkg in "$@"; do
  echo "== $pkg"
  ${capped[@]+"${capped[@]}"} gremlins unleash --workers "$workers" --timeout-coefficient "$coefficient" "$pkg"
  code=$?
  (( code == 0 )) || { echo "speckit-guard: gremlins exited with $code on $pkg (137: memory cap reached, 124 or 143: time limit)" >&2; status=1; }
done
exit "$status"
