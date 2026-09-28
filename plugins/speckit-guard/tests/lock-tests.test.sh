#!/usr/bin/env bash
# Tests du hook lock-tests.sh. Lancer : bash tests/lock-tests.test.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/../scripts/lock-tests.sh"
proj=$(mktemp -d)
mkdir -p "$proj/.specify"
export CLAUDE_PROJECT_DIR="$proj"
pass=0; fail=0

run() { # attendu(allow|block) description json
  local expect="$1" desc="$2" json="$3" code
  printf '%s' "$json" | bash "$hook" >/dev/null 2>&1; code=$?
  local got=allow; [[ $code -eq 2 ]] && got=block
  if [[ "$got" == "$expect" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "ECHEC: $desc (attendu $expect, obtenu $got)"; fi
}
w() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}%s}' "$1" "$2" "${3:+,\"agent_type\":\"$3\"}"; }
b() { jq -nc --arg c "$1" --arg a "${2:-}" '{tool_name:"Bash",tool_input:{command:$c}} + (if $a=="" then {} else {agent_type:$a} end)'; }

# Agent principal (implémenteur)
run block "impl écrit un test Go"          "$(w Edit "$proj/internal/auth/login_test.go")"
run block "impl écrit un spec TS"          "$(w Write "$proj/web/src/Login.spec.ts")"
run block "impl écrit dans e2e/"           "$(w Write "$proj/e2e/login.ts")"
run allow "impl écrit du code prod"        "$(w Edit "$proj/internal/auth/login.go")"
run allow "impl écrit dans specs/"         "$(w Write "$proj/specs/003-auth/verification.md")"
run block "impl touche settings.json"      "$(w Edit "$proj/.claude/settings.json")"
run block "impl touche la conf du verrou"  "$(w Write "$proj/.specify/speckit-guard.env")"
run block "impl touche le cache plugin"    "$(w Edit "/home/u/.claude/plugins/cache/x/lock-tests.sh")"
run block "bash sed -i sur un test"        "$(b "sed -i 's/a/b/' internal/auth/login_test.go")"
run block "bash rm d'un test"              "$(b "rm web/src/Login.spec.ts")"
run block "bash git checkout d'un test"    "$(b "git checkout HEAD~1 -- internal/auth/login_test.go")"
run block "bash désactive les hooks"       "$(b "echo '{\"disableAllHooks\":true}' > .claude/settings.local.json")"
run allow "bash lance les tests"           "$(b "go test ./... 2>&1 | tail -20")"
run allow "bash lance un test précis"      "$(b "go test ./internal/auth -run TestLogin > /dev/null")"
run allow "bash git diff"                  "$(b "git diff abc123..HEAD -- internal/auth/login_test.go")"

# test-writer (nom simple et nom préfixé par le plugin)
run allow "writer écrit un test"           "$(w Write "$proj/internal/auth/login_test.go" test-writer)"
run allow "writer préfixé écrit un test"   "$(w Write "$proj/web/src/Login.spec.ts" speckit-guard:test-writer)"
run allow "writer écrit acceptance-tests"  "$(w Write "$proj/specs/003-auth/acceptance-tests.md" test-writer)"
run block "writer écrit du code prod"      "$(w Write "$proj/internal/auth/login.go" test-writer)"
run block "writer touche settings"         "$(w Edit "$proj/.claude/settings.json" test-writer)"

# spec-reviewer
run block "reviewer écrit un fichier"      "$(w Write "$proj/specs/003-auth/verification.md" spec-reviewer)"
run block "reviewer bash écrit"            "$(b "echo x > notes.txt" spec-reviewer)"
run allow "reviewer git diff"              "$(b "git diff abc..HEAD" speckit-guard:spec-reviewer)"

# Hors projet SpecKit
rm -rf "$proj/.specify"
run allow "hors SpecKit : test modifiable" "$(w Edit "$proj/internal/auth/login_test.go")"
mkdir -p "$proj/.specify"

# Échappatoire humaine
TESTS_UNLOCKED=1 run allow "TESTS_UNLOCKED=1" "$(w Edit "$proj/internal/auth/login_test.go")"

# Chemins de test personnalisés
echo "TEST_RE='(^|/)tests/'" > "$proj/.specify/speckit-guard.env"
run block "TEST_RE custom : tests/"        "$(w Write "$proj/tests/api.py")"
run allow "TEST_RE custom : _test.go libre" "$(w Write "$proj/foo_test.go")"

rm -rf "$proj"
echo "$pass OK, $fail échec(s)"
[[ $fail -eq 0 ]]
