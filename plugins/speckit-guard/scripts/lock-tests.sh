#!/usr/bin/env bash
# speckit-guard : hook PreToolUse de verrouillage des tests.
#
# Actif uniquement dans les projets SpecKit (dossier .specify/ présent).
#
# Fichiers verrouillés :
# - Mode « référence » : les fichiers ajoutés par les commits « Référence : <SHA> » des
#   acceptance-tests.md de toutes les features, et ces acceptance-tests.md eux-mêmes. Les autres
#   tests (tests unitaires écrits pendant l'implémentation) restent libres.
# - Mode « motifs » (TEST_RE) tant que la feature courante (branche ou .specify/feature.json)
#   n'a pas encore de référence, ou si une référence est illisible.
#
# Règles :
# - Seul le sous-agent "test-writer" peut créer ou modifier des fichiers verrouillés,
#   et il ne peut écrire QUE des tests ou des docs de feature (specs/).
# - Le sous-agent "spec-reviewer" est en lecture seule.
# - Personne ne peut toucher aux réglages qui désactiveraient le verrou
#   (.claude/settings*.json, cache des plugins, .specify/speckit-guard.env).
#
# Échappatoire humaine : lancer la session avec TESTS_UNLOCKED=1 claude
#
# Personnalisation des chemins de test du mode « motifs » : .specify/speckit-guard.env
#   TEST_RE='...'   (expression régulière étendue, chemin relatif au projet)
#
# Dépendances : jq et git. Sans jq, le verrou reste fermé.

set -uo pipefail

block() {
  echo "speckit-guard: $1" >&2
  exit 2
}

[[ "${TESTS_UNLOCKED:-0}" == "1" ]] && exit 0

input=$(cat)

command -v jq >/dev/null 2>&1 || block "jq introuvable, verrou fermé par sécurité. Installe jq."

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
  sed -n 's/^Référence : *\([0-9a-fA-F]\{7,40\}\).*/\1/p' "$1" 2>/dev/null | head -n1
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
      block "$path protège le verrou des tests, modification interdite depuis Claude Code."
    fi

    case "$agent" in
      spec-reviewer)
        block "le spec-reviewer est en lecture seule, il rend un rapport et ne modifie rien."
        ;;
      test-writer)
        if [[ "$path" =~ $TEST_RE || "$path" =~ $SPECS_RE ]] || is_locked "$path"; then
          exit 0
        fi
        block "le test-writer n'écrit que des tests ou des docs de feature, pas de code de production ni de stub ($path)."
        ;;
    esac

    if [[ "$mode" == reference && "$path" =~ $ACCEPTANCE_DOC_RE ]]; then
      block "$path porte la référence des tests verrouillés, modification interdite pendant l'implémentation."
    fi
    if is_locked "$path"; then
      block "$path est un test d'acceptation verrouillé. Fais évoluer le code, pas les tests. Si un test te semble faux ou contradictoire avec la spec, arrête-toi et signale-le à l'humain."
    fi
    exit 0
    ;;

  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    clean=$(sed -E 's/[0-9]*>&[0-9]+//g; s/[0-9&]*>>?[[:space:]]*\/dev\/null//g' <<<"$cmd")

    [[ "$clean" =~ $WRITE_OPS_RE ]] || exit 0

    if grep -Eq "$PROTECTED_BASH_RE" <<<"$clean"; then
      block "commande qui touche aux réglages du verrou des tests, interdite."
    fi
    if [[ "$agent" == "spec-reviewer" ]]; then
      block "le spec-reviewer est en lecture seule (git diff, git log, lancement des tests uniquement)."
    fi
    if [[ "$agent" != "test-writer" ]] && bash_touches_locked "$clean"; then
      block "commande qui modifie des tests d'acceptation verrouillés, interdite."
    fi
    exit 0
    ;;
esac

exit 0
