#!/usr/bin/env bash
# Tests for count-criteria.sh. Run: bash tests/count-criteria.test.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/count-criteria.sh"
proj=$(mktemp -d)
trap 'rm -rf "$proj"' EXIT
pass=0; fail=0

check() { # description expected-exit expected-output-substring args...
  local desc="$1" want="$2" text="$3" out code; shift 3
  out=$(bash "$script" "$@" 2>&1); code=$?
  if [[ $code -eq $want && "$out" == *"$text"* ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $desc (exit $code)"; echo "$out"; fi
}

git -C "$proj" init -q -b main
mkdir -p "$proj/.specify" "$proj/specs/001-x"
spec="$proj/specs/001-x/spec.md"
cat > "$spec" <<'EOF'
# Feature Specification: X

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Log in (Priority: P1)

**Acceptance Scenarios**:

1. **Given** an account, **When** it logs in, **Then** it sees its page.
2. **Given** a wrong password, **When** it logs in, **Then** it is refused.

### User Story 2 - Log out (Priority: P2)

1. **Étant donné** une session, **When** elle se déconnecte, **Then** la session est close.

### Edge Cases

- What happens when the account is locked?
- What happens when the clock drifts?
  - a nested detail that is not a criterion

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST hash passwords.
- **AUTH-02**: Sessions expire.
  - **AUTH-02a Idle** : after 30 minutes.
  - **AUTH-02b Absolute** : after 12 hours.
- **FR-001**: listed twice, counted once.

## Success Criteria *(mandatory)*

- **SC-001**: 95 % of logins take less than a second.
EOF

check "counts each kind and the leaves only" 0 "scenarios 3, edge cases 2, requirements 3, success criteria 1: 9 criteria (limit 60)" "$spec"
check "lists the scenarios of each story"   0 "User Story 2 - Log out (Priority: P2): 1 scenarios" "$spec"
check "over the limit given as argument"    1 "9 criteria (limit 8)" "$spec" 8
check "at the limit"                        0 "9 criteria (limit 9)" "$spec" 9
echo "MAX_CRITERIA='5'" > "$proj/.specify/speckit-guard.env"
check "limit read from speckit-guard.env"   1 "(limit 5)" "$spec"
check "argument wins over the env file"     0 "(limit 20)" "$spec" 20
check "limit that is not a number"          2 "must be a number" "$spec" abc
check "missing spec"                        2 "usage" "$proj/none.md"

echo "$pass passed, $fail failed"
(( fail == 0 ))
