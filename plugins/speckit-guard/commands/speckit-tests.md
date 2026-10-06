---
description: Has an isolated subagent write the feature's acceptance tests before implementation, proves they fail, and freezes them in a reference commit.
argument-hint: "[feature directory, e.g. specs/003-user-auth]"
---

Goal: produce the feature's acceptance tests **before** `/speckit-implement`, written by a subagent that only sees the spec. These tests become the locked target of the implementation.

Run this command just before implementing the feature, once the features it depends on are merged. Tests written further ahead rely on interfaces that earlier implementations may still change.

Optional argument: $ARGUMENTS

Language: talk to the user in the language they use in this conversation. Files you write in `specs/` follow the language of `spec.md`.

## 1. Resolve the feature

In this order:
1. The directory passed as argument.
2. `specs/<current git branch>/`.
3. The `specs/*/` directory whose `spec.md` is the most recent.

If nothing matches, or if the choice is ambiguous, ask the human. Check that `spec.md` exists. If `acceptance-tests.md` already exists, ask whether to complete it or start over.

## 2. Starting state

- The git tree must be clean; otherwise ask the human to commit or stash first.
- Detect the project's test commands (for example `go test ./...`, and the frontend test script if there is one) and run the suite. If it is already red, stop and report it: the new tests cannot be proven red on a broken base.

## 3. Interface skeleton

The tests must compile and run, so that a mistake in a test shows up now and not during implementation.

From `plan.md` and `contracts/` only, create the public interfaces the tests will call and that do not exist yet: types, function and method signatures, exported components. Every body fails explicitly (`panic("not implemented")` in Go, `throw new Error("not implemented")` in TypeScript). No logic and no plausible return value.

The project must still build (for example `go vet ./...`, `tsc --noEmit`) and the existing suite must stay green. Commit the skeleton alone: `chore(<feature>): interface skeleton`. Skip this step if the plan defines no new interface.

## 4. Delegate to the test-writer

Launch the `test-writer` subagent with **only**:
- the path of the feature directory,
- the paths of `spec.md`, `plan.md` and `contracts/` if they exist,
- the SHA of the skeleton commit, if there is one,
- the detected test commands.

Pass on neither your interpretation of the spec nor any implementation idea. Its isolation is the whole point of this step.

You cannot write the tests yourself: the project's lock prevents it.

If `acceptance-tests.md` has a non-empty "Missing interfaces" section, add those signatures to the skeleton exactly as listed, with failing bodies, commit them alone (`chore(<feature>): complete interface skeleton`), then launch the `test-writer` again with the same inputs to finish proving red.

## 5. Check its work

- `acceptance-tests.md` exists and every criterion of the spec appears in it, either as a test or in the "Not covered" section.
- Run every listed test yourself: all of them must fail, on an assertion or on "not implemented", never on a compile or import error. Report any passing test to the human.
- Look for disabled tests (skip, todo, only) in the added files.
- Only test files and files under `specs/` have changed (`git status`).
- If the "Conflicts with other features" part of the spec ambiguities is not empty, stop before freezing. Show the conflicts to the human and ask whether to fix the specs first (then run the `test-writer` again) or freeze as is.

## 6. Freeze the reference

Commit the tests and `acceptance-tests.md` alone, with a message of the form `test(<feature>): acceptance tests (red)`. Then add a line `Reference: <short SHA>` at the top of `acceptance-tests.md` and commit it. Write this line exactly in that form, in English, whatever the language of the file: the lock and `/speckit-verify` read it.

## 7. Hand back

Short summary:
- criteria covered / total,
- uncovered criteria and ambiguities to resolve (these first, because an unresolved ambiguity produces code that matches the tests but misses the intent),
- the two or three tests to review first.

Remind the human that the tests are now locked and that the next steps are `/speckit-implement`, then `/speckit-verify`. If a locked test turns out to be broken during implementation, `/speckit-fix-test` has the `test-writer` repair it without unlocking anything.
