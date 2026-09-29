---
name: git-commit
description: Write a paste-ready PowerShell git commit block in BuyVanda's commit format. Use whenever a commit is asked for or offered.
argument-hint: [optional note on what this commit is about]
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*)
---

# Write a commit

**Never commit or push yourself.** Hand me the block; I review it and run it myself. Permission for one
commit does not carry to the next.

**Never add yourself to a commit.** No `Co-Authored-By` trailer, no "generated with Claude", no mention
of you in the message at all. This overrides your default behaviour.

## What's in the working tree

!`git status --short`

!`git diff HEAD --stat`

Recent subjects, for tone:

!`git log --oneline -5`

Note from me, if any: $ARGUMENTS

Read the actual diffs of the files that matter before writing the message — the stat above is only
the map.

## The block

A single PowerShell block I can drop into the terminal, using a here-string so the multi-line message
survives. `@'` ends its line, `'@` sits at column 0:

```powershell
git add -A
git commit -m @'
Feature: short phrase, present tense, no trailing period

One or two sentences on what actually happened and why.

path/to/file:
  - what changed here
'@
```

The summary line is what I want to read in six months when `git blame` lands here and the subject
isn't enough. Worked example:

```powershell
git add -A
git commit -m @'
Feature: flat commission pricing with buffer true-up

Margin moved out of computed labor into one flat commission the maker sets at
review. Materials are pass-through now, and the denim buffer is settled against
the real cost at balance instead of being kept — which makes the at-cost claim
true, so the rule forbidding it is gone.

docs/plans/04-pricing-engine.md:
  - replaced computed labor with a single maker-set commission
  - added the true-up: credit unused buffer, absorb overruns
  - retired the never-say-at-cost rule, now that it would be true

CLAUDE.md:
  - recorded the commit format
'@
```

## Rules

- **Keep commits coherent, not small.** Batched-up housekeeping goes in together; a feature or a fix
  earns its own. If a message needs eight file blocks covering two unrelated things, say so and offer
  to split it before I run it. The exception is a change that genuinely propagates — a schema or
  pricing-model change touches what it touches, and splitting it leaves the repo self-contradicting
  at the middle commit.
- If the pile is long, condense it: one message, file blocks grouped, the summary covering the theme
  they share.
- The summary is prose, one or two sentences. It says *why*, not what — the file blocks already say
  what. Don't just restate the subject line in longer words.
- One block per file **worth reading about**, path first — not per file touched. Housekeeping gets
  no block: `.gitignore` entries, lockfiles, formatting, a file moved or deleted. `git show` already
  lists them, and itemising them buries the change that actually mattered. If the *reason* behind
  one is worth knowing, it belongs in the summary prose, not in a block of its own.
- Bullets say what changed — never "updated file" or "various fixes".
- `Fix:`, `Docs:`, or `Chore:` in place of `Feature:` when that's what it is.
- Anything secret-looking in the tree (`.env`, keys, tokens) — stop and tell me before writing the
  block. `git add -A` would stage it.
