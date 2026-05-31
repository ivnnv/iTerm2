# Local overlay branches (`local/*`)

These `local/*` branches are **personal, cross-machine integration branches**.
They are pushed to my fork (`origin`, ivnnv/iTerm2) only so I can build the same
daily driver on another machine. They are **not** upstream pull requests and must
never be opened as PRs against gnachman/iTerm2.

## The convention

For an upstream PR branch `X`:

- `X` stays **pristine**: it mirrors exactly what's in the open PR, nothing extra.
- `local/X` is the **overlay**: `X` plus the fixes or cross-branch dependencies that
  the PR can't carry yet (for example, code that depends on another PR not yet
  merged). This is what I actually build and run.

A `daily-driver` integration branch should hold as little as possible; prefer the
relevant `local/*` branch instead.

## Branches in flight (as of 2026-05-31)

Two coupled upstream PRs:

- **`codex-title-adaptor`** = PR #673. Detects Codex CLI working state from the
  terminal title and exposes it as a synthesized tab status (working / idle).
- **`ai-menu-bar-status`** = PR #670 (draft). Menu-bar item that counts working AI
  agents. It consumes the status model from #673. It is based on old `master`, so on
  its own it does not contain that model.

The overlays:

- **`local/codex-title-adaptor`** = `codex-title-adaptor` + the `isBusy` fix.
  `isBusy` makes consumers count only agents actively working: synthesized
  working/waiting, or a non-owned OSC 21337 status whose `statusText` is not an
  explicit `Idle` label (Claude Code keeps an indicator dot while idle). It lives
  here, not on the PR branch, because #673 stays pristine until the maintainer
  reviews it. Verified by tests in `ModernTests/CodexTitleStatusAdaptorTests.swift`.

- **`local/ai-menu-bar-status`** = `local/codex-title-adaptor` + `ai-menu-bar-status`
  + a one-line glue commit (`busyCount` filters on `isBusy` instead of
  `hasIndicator`). This is the branch to build and daily-drive. The glue can't live
  on #670 because that branch lacks the synthesized status model.

## Why the split

The bug was: the menu-bar count never dropped to 0. Two separate "a dot means busy"
mistakes: Codex's idle shows a green dot, and Claude Code keeps its dot while idle and
signals state through `statusText`. `isBusy` fixes both. The fix spans the model
(#673's files) and the menu bar (#670's file), so it can only run combined, which is
exactly what `local/ai-menu-bar-status` is for.

## Build / daily-drive

```
git checkout local/ai-menu-bar-status
tools/build.sh
# then copy the built app where you want it, e.g.:
# ditto ~/Library/Developer/Xcode/DerivedData/iTerm2-*/Build/Products/Development/iTerm2.app ~/Desktop/iTerm2.app
```

## When #673 lands upstream

Fold the `isBusy` work into the combined menu-bar PR (the menu-bar PR will then carry
both features), then these `local/*` branches can be deleted and rebuilt from the
pristine PR branches if ever needed again.
