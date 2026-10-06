#!/usr/bin/env bash
# speckit-guard: PreToolUse hook that locks the acceptance tests.
#
# Active only in SpecKit projects (a .specify/ directory exists).
#
# Locked files:
# - "reference" mode: the files added by the "Reference: <SHA>" commits of every feature's
#   acceptance-tests.md, and those acceptance-tests.md files themselves. Other tests
#   (unit tests written during implementation) stay editable.
# - "patterns" mode (TEST_RE) while the current feature (branch or .specify/feature.json)
#   has no reference yet, or if a reference cannot be read.
#
# Rules:
# - Only the "test-writer" subagent may create or modify locked files,
#   and it may write ONLY tests or feature docs (specs/).
# - The "spec-reviewer" subagent is read-only.
# - Nobody may touch the settings that would disable the lock
#   (.claude/settings*.json, plugin cache, .specify/speckit-guard.env).
#
# Repairing a broken locked test: /speckit-fix-test, through the test-writer.
# Human escape hatch: start the session with TESTS_UNLOCKED=1 claude
#
# Custom test paths for "patterns" mode: .specify/speckit-guard.env
#   TEST_RE='...'   (extended regular expression, path relative to the project)
#
# Dependencies: jq and git. Without jq, the lock stays closed.

set -uo pipefail

block() {
  echo "speckit-guard: $1" >&2
  exit 2
}

[[ "${TESTS_UNLOCKED:-0}" == "1" ]] && exit 0

input=$(cat)

command -v jq >/dev/null 2>&1 || block "jq not found, the lock stays closed for safety. Install jq."

tool=$(jq -r '.tool_name // ""' <<<"$input")
agent=$(jq -r '.agent_type // ""' <<<"$input")
project="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // ""' <<<"$input")}"

[[ -d "$project/.specify" ]] || exit 0

agent="${agent##*:}"

TEST_RE='(_test\.go$|\.(spec|test)\.(ts|tsx|js|mjs|vue)$|(^|/)(__tests__|e2e|testdata)/)'
conf="$project/.specify/speckit-guard.env"
if [[ -f "$conf" ]]; then
  custom=$(grep -E '^TEST_RE=' "$conf" | tail -n1 | cut -d= -f2- | sed -E "s/^['\"]//; s/['\"]$//")
  [[ -n "$custom" ]] && TEST_RE="$custom"
fi

SPECS_RE='^specs/'
ACCEPTANCE_DOC_RE='^specs/[^/]+/acceptance-tests\.md$'
PROTECTED_RE='(^|/)\.claude/(settings(\.local)?\.json|plugins/)|(^|/)\.specify/speckit-guard\.env$'
PROTECTED_BASH_RE='\.claude/(settings|plugins)|speckit-guard\.env|disableAllHooks'
TEST_BASH_RE='(_test\.go|\.(spec|test)\.(ts|tsx|js|mjs|vue)|__tests__|/e2e/|testdata/)'
WRITE_OPS_RE='(>|\btee\b|\bsed[[:space:]]+(-[a-zA-Z]*i|--in-place)|\bperl[[:space:]]+-[a-zA-Z]*i|\brm\b|\bmv\b|\bcp\b|\btruncate\b|\bpatch\b|\bdd\b|\binstall\b|\bgit[[:space:]]+(checkout|restore|rm|mv|stash|reset|apply|am|cherry-pick|revert)\b)'
DESTRUCTIVE_RE='(\brm\b|\bmv\b|\btruncate\b|\bsed[[:space:]]+(-[a-zA-Z]*i|--in-place)|\bperl[[:space:]]+-[a-zA-Z]*i|\bgit[[:space:]]+(checkout|restore|rm|mv|stash|reset|apply|am|cherry-pick|revert)\b)'

rel() {
  local p="$1"
  p="${p#"$project"/}"
  p="${p#./}"
  printf '%s' "$p"
}

ref_of() {
  sed -nE 's/^(Reference|Référence) *: *([0-9a-fA-F]{7,40}).*/\2/p' "$1" 2>/dev/null | head -n1
}

current_feature_dir() {
  local branch fdir
  branch=$(git -C "$project" branch --show-current 2>/dev/null)
  if [[ -n "$branch" && -d "$project/specs/$branch" ]]; then
    printf 'specs/%s' "$branch"
    return
  fi
  if [[ -f "$project/.specify/feature.json" ]]; then
    fdir=$(jq -r '.feature_directory // ""' "$project/.specify/feature.json" 2>/dev/null)
    fdir=$(rel "$fdir")
    [[ -n "$fdir" && -d "$project/$fdir" ]] && printf '%s' "$fdir"
  fi
}

mode=patterns
locked=()
cur=$(current_feature_dir)
if [[ -z "$cur" || -n "$(ref_of "$project/$cur/acceptance-tests.md")" ]]; then
  refs=()
  for doc in "$project"/specs/*/acceptance-tests.md; do
    [[ -f "$doc" ]] || continue
    r=$(ref_of "$doc")
    [[ -n "$r" ]] && refs+=("$r")
  done
  mode=reference
  if (( ${#refs[@]} )); then
    if listing=$(git -C "$project" show --name-only --diff-filter=A --format= "${refs[@]}" -- . ':(exclude)specs' 2>/dev/null); then
      mapfile -t locked < <(grep -v '^$' <<<"$listing" | sort -u)
    else
      mode=patterns
    fi
  fi
fi

is_locked() {
  local p="$1" f
  if [[ "$mode" == patterns ]]; then
    [[ "$p" =~ $TEST_RE ]]
    return
  fi
  for f in "${locked[@]}"; do
    [[ "$p" == "$f" ]] && return 0
  done
  return 1
}

bash_touches_locked() {
  local c="$1" f
  if [[ "$mode" == patterns ]]; then
    grep -Eq "$TEST_BASH_RE" <<<"$c"
    return
  fi
  grep -Eq 'acceptance-tests\.md' <<<"$c" && return 0
  for f in "${locked[@]}"; do
    [[ "$c" == *"$(basename "$f")"* ]] && return 0
    [[ "$c" =~ $DESTRUCTIVE_RE && "$c" == *"$(dirname "$f")"* ]] && return 0
  done
  return 1
}

case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit)
    raw=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
    path=$(rel "$raw")

    if [[ "$raw" =~ $PROTECTED_RE || "$path" =~ $PROTECTED_RE ]]; then
      block "$path protects the test lock and cannot be modified from Claude Code."
    fi

    case "$agent" in
      spec-reviewer)
        block "the spec-reviewer is read-only: it returns a report and modifies nothing."
        ;;
      test-writer)
        if [[ "$path" =~ $TEST_RE || "$path" =~ $SPECS_RE ]] || is_locked "$path"; then
          exit 0
        fi
        block "the test-writer only writes tests or feature docs, no production code or stub ($path)."
        ;;
    esac

    if [[ "$mode" == reference && "$path" =~ $ACCEPTANCE_DOC_RE ]]; then
      block "$path holds the reference of the locked tests and cannot be modified during implementation. To repair a broken acceptance test, run /speckit-guard:speckit-fix-test <test file>."
    fi
    if is_locked "$path"; then
      block "$path is a locked acceptance test. Change the code, not the tests. If the test itself is broken (compile error, fixture, typo) or contradicts the spec, run /speckit-guard:speckit-fix-test $path; a subagent that cannot run it reports the raw failure to its caller."
    fi
    exit 0
    ;;

  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    clean=$(sed -E 's/[0-9]*>&[0-9]+//g; s/[0-9&]*>>?[[:space:]]*\/dev\/null//g' <<<"$cmd")

    [[ "$clean" =~ $WRITE_OPS_RE ]] || exit 0

    if grep -Eq "$PROTECTED_BASH_RE" <<<"$clean"; then
      block "this command touches the test lock settings and is not allowed."
    fi
    if [[ "$agent" == "spec-reviewer" ]]; then
      block "the spec-reviewer is read-only (git diff, git log and running tests only)."
    fi
    if [[ "$agent" != "test-writer" ]] && bash_touches_locked "$clean"; then
      block "this command modifies locked acceptance tests and is not allowed. To repair a broken acceptance test, run /speckit-guard:speckit-fix-test <test file>."
    fi
    exit 0
    ;;
esac

exit 0
