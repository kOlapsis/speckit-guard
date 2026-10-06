---
description: Has the isolated test-writer repair a broken locked acceptance test during implementation, and records the change as a reviewed amendment.
argument-hint: "<test file> [test name]"
---

Goal: let the implementation go on when a locked acceptance test is itself broken (compile error, fixture, typo, contradiction with the spec), without letting the implementer edit it. The `test-writer` decides and repairs; the change stays traceable for `/speckit-verify`.

Arguments: $ARGUMENTS

Language: talk to the user in the language they use in this conversation. Files you write in `specs/` follow the language of `spec.md`.

## 1. Find the test and its feature

The feature is the one whose `specs/*/acceptance-tests.md` lists the test file. If no feature lists it, it is not a locked acceptance test: say so and stop, the implementer can edit it directly.

## 2. Reproduce

Run the test alone, with the command given in `acceptance-tests.md`. Keep the raw output (the last 60 lines are enough). If it passes, stop and say so.

## 3. Delegate to the test-writer

Launch the `test-writer` subagent in repair mode with **only**:
- the path of the feature directory,
- the paths of `spec.md`, `plan.md` and `contracts/` if they exist,
- the test file, the test name if given, and the command to run it,
- the raw output of step 2.

Pass on neither the implementer's diagnosis nor what it would like the test to expect. You cannot edit the test yourself: the lock prevents it.

## 4. Check its work

- Among locked files, only this feature's acceptance test files and its `acceptance-tests.md` have changed (`git diff --name-only`). Other uncommitted changes belong to the implementation: leave them alone.
- The `Reference:` line is unchanged.
- For FIXED: there is an entry in the "Amendments" section, and the test now compiles. Run it again and keep the result.

## 5. Commit

Commit only the files changed by the `test-writer`, with a pathspec so that the implementation in progress stays out of the commit:
- FIXED: `git commit -m "test(<feature>): fix <test name>" -- <test files> specs/<feature>/acceptance-tests.md`
- CONFLICT: `git commit -m "docs(<feature>): record spec conflict on <test name>" -- specs/<feature>/acceptance-tests.md`
- REFUSED: nothing to commit.

## 6. Hand back

One line with the verdict and what to do next:
- FIXED: resume the implementation; give the new result of the test.
- REFUSED: the test reflects the spec, change the code. Give the `test-writer`'s explanation.
- CONFLICT: leave the tasks that depend on this test, carry on with the others. `/speckit-verify` will report the conflict to the human.
