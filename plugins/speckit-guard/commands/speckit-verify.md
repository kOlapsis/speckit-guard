---
description: Checks a feature's implementation against its spec with a fresh-context reviewer, after mechanical checks (test integrity, full suite, mutation testing).
argument-hint: "[feature directory, e.g. specs/003-user-auth]"
---

Goal: judge whether the implementation does what the spec asks, not just whether the tests pass. This command fixes nothing; it produces a verdict and a list of gaps.

Optional argument: $ARGUMENTS

Language: talk to the user in the language they use in this conversation. Files you write in `specs/` follow the language of `spec.md`.

## 1. Resolve the feature and the reference

Resolve the feature directory like `/speckit-tests` (argument, then `specs/<current branch>/`, then the most recent `spec.md`, otherwise ask).

Read the reference SHA from the `Reference:` line of `acceptance-tests.md` (older features may use `Référence :`). If there is none, stop: `/speckit-tests` must run first.

## 2. Mechanical checks (before any judgement)

1. **Test integrity**: list the test files added in the reference commit and check with `git diff <SHA>..HEAD` that none has changed. If one has changed, the verdict is FAIL, whatever the rest.
2. **Full suite**: run all of the project's test commands. Record the result.
3. **Mutation testing, if the tool is already installed** (do not install it yourself):
   - Go: `gremlins` on the packages changed since the reference.
   - Frontend: Stryker, only if it is configured in the project.
   Record the score and the surviving mutants in the changed code. If no tool is available, note "mutation testing not run".

## 3. Delegate to the spec-reviewer

Launch the `spec-reviewer` subagent with **only**:
- the path of the feature directory,
- the reference SHA,
- the raw results of the mechanical checks.

Pass on no summary of the implementation and no opinion of your own: it must judge cold, from the spec and the diff.

## 4. Record

Write `verification.md` in the feature directory: date, SHA of `HEAD`, mechanical results, then the reviewer's report as is.

If the verdict is FAIL or if some criteria are PARTIAL or MISSING, append to `tasks.md` a "Remediation (verify)" section, in the language of `tasks.md`, with one task per gap.

## 5. Hand back

Give the overall verdict in one line, the main gaps, and what the human must test by hand. Fix nothing in this command.
