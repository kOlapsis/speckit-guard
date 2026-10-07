# speckit-guard

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

**Your coding agent should not be the one grading its own work.**

speckit-guard is a [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin for [GitHub Spec Kit](https://github.com/github/spec-kit). It has acceptance tests written from the spec before any code exists, locks them while `/speckit-implement` runs, and then has a reviewer with a fresh context check the implementation against the spec, criterion by criterion.

[Version française](README.fr.md)

## The problem

In spec-driven development with Spec Kit, the agent that implements a feature also writes its tests and decides when the feature is done. When a test fails, the shortest path to green is often to edit the test instead of the code. The default flow has no step that checks for this, so "all tests pass" says little about whether the spec is met.

## What speckit-guard adds

1. **`/speckit-tests`**: a skeleton of the planned interfaces is created first, so that the tests compile. Then an isolated subagent (`test-writer`) reads only the spec, writes the acceptance tests before implementation, and proves they fail at runtime. It also flags contradictions with the other features' specs. The tests are committed, and that commit becomes the reference.
2. **A lock on the tests**: during `/speckit-implement`, a `PreToolUse` hook prevents the agent from modifying those tests. It has to change the code, not the target. If a locked test is itself broken, `/speckit-fix-test` has the `test-writer` repair it and records the change as an amendment, without stopping the run.
3. **`/speckit-verify`**: mechanical checks first (no change to the tests since the reference commit other than amendments, full test suite, mutation testing if a tool is installed), then a `spec-reviewer` subagent that never saw the implementation reasoning judges each acceptance criterion as OK, PARTIAL or MISSING. Gaps are appended to `tasks.md` as remediation tasks.

## Workflow

Run `/speckit-tests` for a feature just before implementing it, once the features it depends on are merged, not for every feature in advance: tests written too early rely on interfaces that earlier implementations may still change.

```
/speckit-specify → /speckit-plan → /speckit-tasks    Spec Kit, unchanged
/speckit-tests      red acceptance tests, reference commit
/speckit-implement  Spec Kit, unchanged, runs into tests it cannot edit
  /speckit-fix-test   only when a locked test is itself broken
/speckit-verify     PASS / FAIL verdict, gaps added to tasks.md
```

When the implementing agent tries to edit a locked test, the hook blocks the tool call and tells it why:

```
speckit-guard: tests/e2e/login.spec.ts is a locked acceptance test. Change the code,
not the tests. If the test itself is broken (compile error, fixture, typo) or contradicts
the spec, run /speckit-guard:speckit-fix-test tests/e2e/login.spec.ts; a subagent that
cannot run it reports the raw failure to its caller.
```

## Installation

The repository is a plugin marketplace named `kolapsis`. In Claude Code:

```
/plugin marketplace add https://github.com/kOlapsis/speckit-guard.git
/plugin install speckit-guard@kolapsis
```

To try a local change before publishing, use the path to a clone instead of the URL.

### Requirements

- Claude Code.
- A project initialized with Spec Kit (a `.specify/` directory). Elsewhere the plugin does nothing.
- `git` and `jq`. Without `jq`, the lock stays closed as a safety measure. If the reference commit is missing from the history (shallow clone), the lock falls back to path patterns.

To limit the plugin to some projects, enable it at project level rather than user level (`enabledPlugins` in the project's `.claude/settings.json`).

### Stacks

The commands let the agent detect and run your project's test commands, so the workflow is not tied to a language. Two parts are more specific:

- The default lock patterns target Go and JavaScript/TypeScript test files. They only apply before the reference commit exists, and can be changed (see below).
- Mutation testing runs only if the tool is already installed: `gremlins` for Go, Stryker for the frontend if configured. The plugin never installs them.
- `gremlins` runs through `scripts/mutation-go.sh`, package by package, under a memory cap (a `systemd-run --user` scope, otherwise `ulimit -v`) and a time limit, so that a mutant that loops while allocating cannot exhaust the machine's memory. Settings: `SPECKIT_MUTATION_MEMORY` (4G), `SPECKIT_MUTATION_WORKERS` (2), `SPECKIT_MUTATION_TIMEOUT_COEFFICIENT` (10), `SPECKIT_MUTATION_PACKAGE_TIMEOUT` (1800 seconds).

## Lock rules

| Who | Locked tests | Other tests | Production code | `specs/` | Lock settings |
|---|---|---|---|---|---|
| Main agent | blocked | allowed | allowed | allowed, except `acceptance-tests.md` | blocked |
| `test-writer` | allowed | allowed | blocked | allowed | blocked |
| `spec-reviewer` | blocked | blocked | blocked | blocked | blocked |

**Which tests are locked.** Once the current feature (branch `NNN-name`, otherwise `.specify/feature.json`) has a `Reference: <SHA>` line in its `acceptance-tests.md`, the lock covers the files added by the reference commits of every feature, plus the `acceptance-tests.md` files themselves. The older French form `Référence : <SHA>` is still read. Unit tests written during implementation stay editable.

While the current feature has no reference yet (during `/speckit-tests`), or if a reference cannot be found in the history, the lock falls back to path patterns. Defaults: `*_test.go`, `*.spec.*` / `*.test.*` (ts, tsx, js, mjs, vue), `__tests__/`, `e2e/`, `testdata/`. To change them, create `.specify/speckit-guard.env`:

```
TEST_RE='(^|/)tests/|_test\.go$'
```

That file is itself protected from the agent. This setting applies to file-writing tools only; Bash commands are checked against a fixed set of patterns.

**Repairing a locked test**: `/speckit-fix-test <test file>` passes the failure to the `test-writer`, without the implementer's diagnosis. The `test-writer` fixes the test if it is wrong (FIXED), refuses if it matches the spec (REFUSED), or records the question if two specs disagree (CONFLICT). A fix is committed alone and listed in the "Amendments" section of `acceptance-tests.md`; `/speckit-verify` has the `spec-reviewer` check that no amendment weakened a test.

**Escape hatch for humans**: start the session with `TESTS_UNLOCKED=1 claude` to fix a test by hand. The agent cannot change this variable.

## Limitations

- Bash command filtering is heuristic. A determined agent can write a file through an indirect route, such as an inline script. The hook stops the common cases, not an adversary.
- **The real guarantee is `/speckit-verify`**: it checks with `git log` and `git diff` that the tests changed only through amendments since the reference commit, independently of the hook. The same check can run in CI.
- A green test does not prove intent. The result is only as good as the acceptance criteria in the spec: resolve the "Spec ambiguities" section of `acceptance-tests.md` before implementing.

## Development

```
bash plugins/speckit-guard/tests/lock-tests.test.sh   # hook tests (requires jq)
claude plugin validate .                               # manifest validation
```

## License

[Apache 2.0](LICENSE)
