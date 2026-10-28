---
description: Checks a feature's implementation against its spec with a fresh-context reviewer, after mechanical checks (test integrity, tests of what changed). Verifies one user story at a time, then a final round.
argument-hint: "[feature directory] [user story, e.g. US2]"
---

Goal: judge whether the implementation does what the spec asks, not just whether the tests pass. This command fixes nothing; it produces a verdict and a list of gaps.

Verify as you go: one round per user story once it is implemented (`/speckit-verify US1`), then a final round without a story before merging. Each round reads and runs only what changed since the previous one, so a gap shows up while it is still cheap to fix.

Optional arguments: $ARGUMENTS

Language: talk to the user in the language they use in this conversation. Files you write in `specs/` follow the language of `spec.md`.

## 1. Resolve the feature, the scope and the checkpoint

Resolve the feature directory like `/speckit-tests` (argument, then `specs/<current branch>/`, then the most recent `spec.md`, otherwise ask).

Scope: a user story given as argument (`US2`, `2` or its title) limits the round to that story. Without one, the round is the final round.

Read the reference SHA from the `Reference:` line of `acceptance-tests.md` (older features may use `Référence :`). If there is none, stop: `/speckit-tests` must run first.

Read the earlier rounds in `verification.md`: each one starts with a line `Verified: <SHA> <scope> <verdict>`. The checkpoint is the SHA of the most recent round, or the reference SHA if there is none.

## 2. Mechanical checks (before any judgement)

1. **Test integrity**, always in full: list the test files added in the reference commit. They may only have changed through amendments made by `/speckit-fix-test`.
   - `git status --porcelain -- <files>`: no uncommitted change.
   - `git log --format='%h %s' <SHA>..HEAD -- <files>`: each of these commits is an amendment. It must be named `test(<feature>): fix ...`, touch only test files and `specs/` (`git show --name-only`), and match an entry of the "Amendments" section of `acceptance-tests.md`.
   If any of these fails, the verdict is FAIL, whatever the rest.
2. **Tests of what changed**: run the feature's acceptance tests and the tests of the packages or modules changed since the checkpoint (`git diff --name-only <checkpoint>..HEAD`). Leave the test tools' caches on (in Go, no `-count=1`).
3. **Full suite, final round only**: run all of the project's test commands, including slow and integration ones, unless an earlier round recorded them green at the current `HEAD`.

Run each command once. Before a run you expect to last more than ten minutes or to start containers, tell the human how long it should take and wait for a yes. Hand any run longer than a few minutes to a subagent on the smallest available model, which waits in its own context and returns, for each command, pass or fail, the duration and the names of the failing tests: never wait for a long run in this conversation, each wake-up rereads its whole context. Record what ran, what was skipped and why.

## 3. Delegate to the spec-reviewer

Launch the `spec-reviewer` subagent with **only**:
- the path of the feature directory,
- the scope: the user story, or `final` with the `Verified:` lines of the earlier rounds,
- the reference SHA and the checkpoint SHA,
- the SHAs of the amendment commits,
- the raw results of the mechanical checks.

Pass on no summary of the implementation and no opinion of your own: it must judge cold, from the spec and the diff.

## 4. Record

Append a section to `verification.md` and keep the earlier rounds. Its first line is `Verified: <short SHA of HEAD> <scope> <verdict>`, in that form and in English whatever the language of the file (scope `US<n>` or `final`, verdict `PASS` or `FAIL`): the next round reads it. Then the date, the mechanical results (commands run, skipped and why), then the reviewer's report as is.

If the verdict is FAIL or if some criteria are PARTIAL or MISSING, append to `tasks.md` a "Remediation (verify)" section, in the language of `tasks.md`, with one task per gap.

## 5. Hand back

Give the overall verdict in one line, the main gaps, the spec conflicts recorded in `acceptance-tests.md` during implementation, and what the human must test by hand. After a story round, the next step is the next story or, once all are done, the final round. Fix nothing in this command.
