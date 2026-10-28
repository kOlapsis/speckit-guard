# speckit-guard

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

**Your coding agent should not be the one grading its own work.**

speckit-guard is a [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin for [GitHub Spec Kit](https://github.com/github/spec-kit). It has acceptance tests written from the spec before any code exists, locks them while `/speckit-implement` runs, and then has a reviewer with a fresh context check the implementation against the spec, criterion by criterion.

[Version française](README.fr.md)

## The problem

In spec-driven development with Spec Kit, the agent that implements a feature also writes its tests and decides when the feature is done. When a test fails, the shortest path to green is often to edit the test instead of the code. The default flow has no step that checks for this, so "all tests pass" says little about whether the spec is met.

## What speckit-guard adds

1. **`/speckit-tests`**: a feature with too many acceptance criteria (more than 60 by default) is stopped first, with a proposed split along its user stories. Then a skeleton of the planned interfaces is created first, so that the tests compile. Then an isolated subagent (`test-writer`) reads only the spec, writes the acceptance tests before implementation, and proves they fail at runtime. It also flags contradictions with the other features' specs. The tests are committed, and that commit becomes the reference.
2. **A lock on the tests**: during `/speckit-implement`, a `PreToolUse` hook prevents the agent from modifying those tests. It has to change the code, not the target. If a locked test is itself broken, `/speckit-fix-test` has the `test-writer` repair it and records the change as an amendment, without stopping the run.
3. **`/speckit-verify`**: mechanical checks first (no change to the tests since the reference commit other than amendments, tests of what changed since the previous round), then a `spec-reviewer` subagent that never saw the implementation reasoning judges each acceptance criterion as OK, PARTIAL or MISSING. It runs once per user story (`/speckit-verify US2`), then a final round runs the full suite and judges only what is left. Gaps are appended to `tasks.md` as remediation tasks.

## Workflow

Run `/speckit-tests` for a feature just before implementing it, once the features it depends on are merged, not for every feature in advance: tests written too early rely on interfaces that earlier implementations may still change.

```
/speckit-specify → /speckit-plan → /speckit-tasks    Spec Kit, unchanged
/speckit-tests      red acceptance tests, reference commit
/speckit-implement  Spec Kit, unchanged, runs into tests it cannot edit
  /speckit-fix-test   only when a locked test is itself broken
  /speckit-verify US<n>  after each user story: its criteria, the diff since the last round
/speckit-verify     final round: full suite, what is left, PASS / FAIL, gaps added to tasks.md
```

Each round of `/speckit-verify` starts its section of `verification.md` with `Verified: <SHA> <scope> <verdict>`. The next round runs only the tests of what changed since that SHA and has the `spec-reviewer` read only that diff, which keeps a round short even on a large feature.

When the implementing agent tries to edit a locked test, the hook blocks the tool call and tells it why:

```
speckit-guard: tests/e2e/login.spec.ts is a locked acceptance test. Change the code,
not the tests. If the test itself is broken (compile error, fixture, typo) or contradicts
the spec, run /speckit-guard:speckit-fix-test tests/e2e/login.spec.ts; a subagent that
cannot run it reports the raw failure to its caller.
```

## One feature per session, with Escouade

Chaining several features in one session makes the context grow with each feature, until it costs more than the work itself. A fresh session per feature costs less and keeps the reviews sharp. [Escouade](https://github.com/guillaume-gagnaire/escouade) (1.7 or later) does this on a Kanban board: one ticket per feature, each run by its own Claude Code agent in its own worktree, with progress on the board and the agent's questions relayed in the window.

Spec Kit and the hook both find the current feature from the branch name, so a ticket must run on the feature branch, not on Escouade's own `escouade/<key>` branch:

1. Create the specs beforehand, in a normal session: `/speckit-specify` for each feature creates the `NNN-name` branch and `specs/NNN-name/`. Then put the project folder back on `main`: a branch checked out there cannot be given to a worktree.
2. Board settings (Settings › Kanban, or `set_board` through the MCP server): target `main`, strategy `merge` so that the reference commit stays reachable from `main` by its SHA (the hook and `/speckit-verify` look it up that way), one ticket at a time, autopilot on.
3. One ticket per feature, with the form's "Branch" field set to the feature branch, each ticket after the previous one. Description:

```
Feature specs/043-public-surfaces-hardening, on its branch.
Run git merge main first. Then, in order: /speckit-plan, /speckit-tasks,
/speckit-guard:speckit-tests, /speckit-implement, /speckit-guard:speckit-verify.
If verify adds remediation tasks, implement them and run verify again.
```

Acceptance criteria worth adding: `acceptance-tests.md` has a `Reference:` line, and the last `/speckit-verify` report has no MISSING criterion.

A ticket waits for the ones before it to be approved, and approval is a click in the window or `approve_ticket` through the MCP server. For an unattended run, a small session with the Escouade MCP server can `wait_ticket` on each ticket and approve it when it rests; its context stays small since it only relays the board. The `git merge main` at the start of each ticket brings in the previous feature and the tests it locked.

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

The commands let the agent detect and run your project's test commands, so the workflow is not tied to a language. One part is more specific:

- The default lock patterns target Go and JavaScript/TypeScript test files. They only apply before the reference commit exists, and can be changed (see below).

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

The same file sets the size limit checked by `/speckit-tests` (scenarios, edge cases, leaf requirements and success criteria of `spec.md`):

```
MAX_CRITERIA=60
```

**Repairing a locked test**: `/speckit-fix-test <test file>` passes the failure to the `test-writer`, without the implementer's diagnosis. The `test-writer` fixes the test if it is wrong (FIXED), refuses if it matches the spec (REFUSED), or records the question if two specs disagree (CONFLICT). A fix is committed alone and listed in the "Amendments" section of `acceptance-tests.md`; `/speckit-verify` has the `spec-reviewer` check that no amendment weakened a test.

**Escape hatch for humans**: start the session with `TESTS_UNLOCKED=1 claude` to fix a test by hand. The agent cannot change this variable.

## Limitations

- Bash command filtering is heuristic. A determined agent can write a file through an indirect route, such as an inline script. The hook stops the common cases, not an adversary.
- **The real guarantee is `/speckit-verify`**: it checks with `git log` and `git diff` that the tests changed only through amendments since the reference commit, independently of the hook. The same check can run in CI.
- A green test does not prove intent. The result is only as good as the acceptance criteria in the spec: resolve the "Spec ambiguities" section of `acceptance-tests.md` before implementing.

## Development

```
bash plugins/speckit-guard/tests/lock-tests.test.sh      # hook tests (requires jq)
bash plugins/speckit-guard/tests/count-criteria.test.sh  # criteria counter tests
claude plugin validate .                                  # manifest validation
```

## License

[Apache 2.0](LICENSE)
