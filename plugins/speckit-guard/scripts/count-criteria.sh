#!/usr/bin/env bash
# speckit-guard: counts the acceptance criteria of a spec and compares them with a limit.
# Usage: count-criteria.sh <spec.md> [limit]
# Limit: the argument, else MAX_CRITERIA in .specify/speckit-guard.env, else 60. Exit 1 when over.
set -uo pipefail

spec="${1:-}"
[[ -f "$spec" ]] || { echo "usage: count-criteria.sh <spec.md> [limit]" >&2; exit 2; }

limit="${2:-}"
if [[ -z "$limit" ]]; then
  root=$(git -C "$(dirname "$spec")" rev-parse --show-toplevel 2>/dev/null)
  conf="${root:-.}/.specify/speckit-guard.env"
  [[ -f "$conf" ]] && limit=$(grep -E '^MAX_CRITERIA=' "$conf" | tail -n1 | cut -d= -f2- | tr -d "'\" ")
fi
limit="${limit:-60}"
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "speckit-guard: the criteria limit must be a number, got '$limit'" >&2; exit 2; }

awk -v limit="$limit" '
  /^#/ {
    edge = ($0 ~ /^###+ +(Edge Cases|Cas limites)/)
    story = ""
    if ($0 ~ /^### +User Story/) { story = $0; sub(/^### +/, "", story); stories[++n] = story }
    next
  }
  /^[[:space:]]*[0-9]+\.[[:space:]]+\*\*(Given|Étant donné)/ { scenarios++; if (story != "") per[story]++; next }
  edge && /^[-*] / { edges++; next }
  /^[[:space:]]*[-*] +\*\*[A-Z][A-Z0-9]*-[0-9]/ {
    match($0, /\*\*[A-Z][A-Z0-9]*-[0-9][0-9A-Za-z]*/)
    ids[substr($0, RSTART + 2, RLENGTH - 2)] = 1
  }
  END {
    for (id in ids) {
      parent = 0
      for (other in ids)
        if (other != id && index(other, id) == 1 && substr(other, length(id) + 1, 1) ~ /[a-z.]/) { parent = 1; break }
      if (parent) continue
      if (id ~ /^SC-/) success++; else requirements++
    }
    total = scenarios + edges + requirements + success
    printf "scenarios %d, edge cases %d, requirements %d, success criteria %d: %d criteria (limit %d)\n", scenarios, edges, requirements, success, total, limit
    for (i = 1; i <= n; i++) printf "  %s: %d scenarios\n", stories[i], per[stories[i]]
    exit (total > limit)
  }
' "$spec"
