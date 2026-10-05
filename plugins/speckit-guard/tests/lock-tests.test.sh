#!/usr/bin/env bash
# Tests for the lock-tests.sh hook. Run: bash tests/lock-tests.test.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/../scripts/lock-tests.sh"
proj=$(mktemp -d)
export CLAUDE_PROJECT_DIR="$proj"
pass=0; fail=0

run() { # expected(allow|block) description json
  local expect="$1" desc="$2" json="$3" code
  printf '%s' "$json" | bash "$hook" >/dev/null 2>&1; code=$?
  local got=allow; [[ $code -eq 2 ]] && got=block
  if [[ "$got" == "$expect" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $desc (expected $expect, got $got)"; fi
}
w() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}%s}' "$1" "$2" "${3:+,\"agent_type\":\"$3\"}"; }
b() { jq -nc --arg c "$1" --arg a "${2:-}" '{tool_name:"Bash",tool_input:{command:$c}} + (if $a=="" then {} else {agent_type:$a} end)'; }
g() { git -C "$proj" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }

mkdir -p "$proj/.specify" "$proj/specs/003-auth"
g init -b main
echo spec > "$proj/specs/003-auth/spec.md"
g add -A; g commit -m init
g checkout -b 003-auth

# "patterns" mode: the current feature has no reference yet.
run block "impl writes a Go test"          "$(w Edit "$proj/internal/auth/login_test.go")"
run block "impl writes a TS spec"          "$(w Write "$proj/web/src/Login.spec.ts")"
run block "impl writes in e2e/"            "$(w Write "$proj/e2e/login.ts")"
run allow "impl writes prod code"          "$(w Edit "$proj/internal/auth/login.go")"
run allow "impl writes in specs/"          "$(w Write "$proj/specs/003-auth/verification.md")"
run block "impl edits settings.json"       "$(w Edit "$proj/.claude/settings.json")"
run block "impl edits the lock config"     "$(w Write "$proj/.specify/speckit-guard.env")"
run block "impl edits the plugin cache"    "$(w Edit "/home/u/.claude/plugins/cache/x/lock-tests.sh")"
run block "bash sed -i on a test"          "$(b "sed -i 's/a/b/' internal/auth/login_test.go")"
run block "bash rm of a test"              "$(b "rm web/src/Login.spec.ts")"
run block "bash git checkout of a test"    "$(b "git checkout HEAD~1 -- internal/auth/login_test.go")"
run block "bash disables hooks"            "$(b "echo '{\"disableAllHooks\":true}' > .claude/settings.local.json")"
run allow "bash runs the tests"            "$(b "go test ./... 2>&1 | tail -20")"
run allow "bash runs one test"             "$(b "go test ./internal/auth -run TestLogin > /dev/null")"
run allow "bash git diff"                  "$(b "git diff abc123..HEAD -- internal/auth/login_test.go")"

run allow "writer writes a test"           "$(w Write "$proj/internal/auth/login_test.go" test-writer)"
run allow "prefixed writer writes a test"  "$(w Write "$proj/web/src/Login.spec.ts" speckit-guard:test-writer)"
run allow "writer writes acceptance-tests" "$(w Write "$proj/specs/003-auth/acceptance-tests.md" test-writer)"
run block "writer writes prod code"        "$(w Write "$proj/internal/auth/login.go" test-writer)"
run block "writer edits settings"          "$(w Edit "$proj/.claude/settings.json" test-writer)"

run block "reviewer writes a file"         "$(w Write "$proj/specs/003-auth/verification.md" spec-reviewer)"
run block "reviewer bash writes"           "$(b "echo x > notes.txt" spec-reviewer)"
run allow "reviewer git diff"              "$(b "git diff abc..HEAD" speckit-guard:spec-reviewer)"

# "reference" mode: only the files of the reference commit are locked.
mkdir -p "$proj/test/acceptance" "$proj/web/e2e"
echo t > "$proj/test/acceptance/auth_test.go"
echo t > "$proj/web/e2e/login.spec.ts"
g add -A; g commit -m "red tests"
ref=$(git -C "$proj" rev-parse --short HEAD)
printf 'Reference: %s\n\n# Tests\n' "$ref" > "$proj/specs/003-auth/acceptance-tests.md"
g add -A; g commit -m "pin"

run block "ref: impl writes an acceptance test"      "$(w Edit "$proj/test/acceptance/auth_test.go")"
run block "ref: impl writes a reference e2e"         "$(w Write "$proj/web/e2e/login.spec.ts")"
run allow "ref: impl writes a unit test"             "$(w Write "$proj/internal/auth/login_test.go")"
run allow "ref: impl writes another TS spec"         "$(w Write "$proj/web/src/Login.spec.ts")"
run allow "ref: impl writes prod code"               "$(w Edit "$proj/internal/auth/login.go")"
run block "ref: impl edits acceptance-tests.md"      "$(w Edit "$proj/specs/003-auth/acceptance-tests.md")"
run allow "ref: impl writes in specs/"               "$(w Write "$proj/specs/003-auth/verification.md")"
run block "ref: bash sed -i on a locked test"        "$(b "sed -i 's/a/b/' test/acceptance/auth_test.go")"
run block "ref: bash rm of the locked directory"     "$(b "rm -rf test/acceptance")"
run block "ref: bash git checkout of a test"         "$(b "git checkout HEAD~1 -- web/e2e/login.spec.ts")"
run block "ref: bash sed on acceptance-tests.md"     "$(b "sed -i 's/^Reference.*//' specs/003-auth/acceptance-tests.md")"
run allow "ref: bash writes a unit test"             "$(b "cat > internal/auth/login_test.go <<EOF
package auth
EOF")"
run allow "ref: bash runs the tests with tee"        "$(b "go test ./test/acceptance/... 2>&1 | tee /tmp/out.log")"
run allow "ref: writer writes a locked test"         "$(w Write "$proj/test/acceptance/auth_test.go" test-writer)"
run allow "ref: writer writes acceptance-tests"      "$(w Write "$proj/specs/003-auth/acceptance-tests.md" test-writer)"

g checkout main
g merge --ff-only 003-auth
run block "ref: on main, acceptance test"            "$(w Edit "$proj/test/acceptance/auth_test.go")"
run allow "ref: on main, unit test"                  "$(w Edit "$proj/internal/auth/login_test.go")"
g checkout 003-auth

mkdir -p "$proj/specs/004-next"
g checkout -b 004-next
run block "next feature without ref: patterns"       "$(w Write "$proj/internal/next/next_test.go")"
g checkout 003-auth

printf 'Reference: deadbee\n' > "$proj/specs/003-auth/acceptance-tests.md"
run block "unreadable ref: pattern lock"             "$(w Write "$proj/internal/auth/login_test.go")"
printf 'Référence : %s\n' "$ref" > "$proj/specs/003-auth/acceptance-tests.md"
run block "legacy French ref marker"                 "$(w Edit "$proj/test/acceptance/auth_test.go")"
run allow "legacy French ref: unit test free"        "$(w Write "$proj/internal/auth/login_test.go")"
printf 'Reference: %s\n' "$ref" > "$proj/specs/003-auth/acceptance-tests.md"

rm -rf "$proj/.specify"
run allow "outside SpecKit: test editable" "$(w Edit "$proj/test/acceptance/auth_test.go")"
mkdir -p "$proj/.specify"

TESTS_UNLOCKED=1 run allow "TESTS_UNLOCKED=1" "$(w Edit "$proj/test/acceptance/auth_test.go")"

g checkout 004-next
echo "TEST_RE='(^|/)tests/'" > "$proj/.specify/speckit-guard.env"
run block "custom TEST_RE: tests/"         "$(w Write "$proj/tests/api.py")"
run allow "custom TEST_RE: _test.go free"   "$(w Write "$proj/foo_test.go")"

rm -rf "$proj"
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
