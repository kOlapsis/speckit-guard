#!/usr/bin/env bash
# Tests for mutation-go.sh. Run: bash tests/mutation-go.test.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/mutation-go.sh"
bin=$(mktemp -d)
pass=0; fail=0

check() { # description condition
  if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi
}

cat >"$bin/gremlins" <<'EOF'
#!/usr/bin/env bash
pkg="${!#}"
echo "args: $*"
case "$pkg" in
  hog) exec python3 -c 'a = bytearray(1024 * 2**20)' ;;
  *) echo "mutated $pkg" ;;
esac
EOF
chmod +x "$bin/gremlins"

out=$(PATH="$bin:$PATH" bash "$script" 2>&1); code=$?
check "no package is a usage error" '[[ $code -eq 2 ]]'

out=$(PATH="$bin/none" "$BASH" "$script" ./pkg 2>&1); code=$?
check "missing gremlins exits 3" '[[ $code -eq 3 && "$out" == *"not installed"* ]]'

out=$(PATH="$bin:$PATH" bash "$script" ok 2>&1); code=$?
check "clean run exits 0" '[[ $code -eq 0 && "$out" == *"mutated ok"* ]]'
check "default flags" '[[ "$out" == *"--workers 2 --timeout-coefficient 10 ok"* ]]'

out=$(PATH="$bin:$PATH" SPECKIT_MUTATION_WORKERS=1 SPECKIT_MUTATION_TIMEOUT_COEFFICIENT=5 bash "$script" ok 2>&1)
check "flags from the environment" '[[ "$out" == *"--workers 1 --timeout-coefficient 5 ok"* ]]'

if command -v python3 >/dev/null 2>&1; then
  out=$(PATH="$bin:$PATH" SPECKIT_MUTATION_MEMORY=200M bash "$script" hog after 2>&1); code=$?
  check "runaway package is stopped by the memory cap" '[[ $code -eq 1 && "$out" == *"exited with"*"on hog"* ]]'
  check "next package still runs" '[[ "$out" == *"mutated after"* ]]'
fi

rm -rf "$bin"
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
