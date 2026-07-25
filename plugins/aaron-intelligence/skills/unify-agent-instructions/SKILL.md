---
name: unify-agent-instructions
description: Use when making AGENTS.md the canonical agent-instructions file in a repo and CLAUDE.md a symlink to it — migrating an existing CLAUDE.md, setting up a new repo, or auditing which repos still have a standalone or duplicate CLAUDE.md.
disable-model-invocation: true
---

# AGENTS.md canonical, CLAUDE.md a symlink

One instructions file per repo. `AGENTS.md` holds the content; `CLAUDE.md` is a
git-tracked symlink to it (mode `120000`).

`AGENTS.md` is the cross-tool convention and Claude Code follows the symlink, so
every tool reads the same file. Two real files drift, and each tool silently
reads different rules — that's the thing being prevented.

## 1. Classify

Read-only — do not `pull` or otherwise write before classifying. A `pull` acts
on whatever branch happens to be checked out, which may be dirty, detached,
upstream-less, or an intentionally stale feature branch; fetch/compare instead
if branch freshness matters, and treat updating the checkout as an explicit
step the user asks for separately.

```bash
git status --short --branch                # branch, dirty/untracked state
ls -la AGENTS.md CLAUDE.md 2>/dev/null      # untracked files `git ls-files` would miss
git ls-files -s AGENTS.md CLAUDE.md         # tracked only: 100644 = file, 120000 = symlink
git show :CLAUDE.md 2>/dev/null             # if CLAUDE.md is 120000, prints its link target
```

`git ls-files -s` reports the index only — it shows mode, not target, and says
nothing about an untracked file. Mode `120000` on its own does not mean
"done": the link could point at the wrong file. Confirm the target with
`git show :CLAUDE.md` before treating it as healthy.

| State | Do |
|---|---|
| `CLAUDE.md` exists (tracked or not), no `AGENTS.md` | `git mv CLAUDE.md AGENTS.md` (untracked: `mv` then `git add`), then link |
| `AGENTS.md` exists, no `CLAUDE.md` | link |
| `CLAUDE.md` is tracked `120000`, `git show :CLAUDE.md` prints exactly `AGENTS.md`, and `AGENTS.md` is tracked `100644` | done |
| `CLAUDE.md` is tracked `120000` but the target isn't exactly `AGENTS.md` | **stop** — report the target |
| Both exist as `100644`, `CLAUDE.md` is a **stub** | `git rm CLAUDE.md`, then link |
| Both exist as `100644`, both real | **stop** — `diff` them, user merges into `AGENTS.md` first |

A **stub** is a `CLAUDE.md` that only points at `AGENTS.md` — `@AGENTS.md`, or a
line of prose saying "follow AGENTS.md". It's this same idea hand-rolled, so
replacing it loses nothing. Read it first: one unique rule in there and it's a
real file, not a stub. Under ~300B is a good hint.

## 2. Link

```bash
ln -s AGENTS.md CLAUDE.md
git add CLAUDE.md
git ls-files -s CLAUDE.md      # must be 120000, else you committed a text file
```

Target is the bare sibling name — never an absolute path, which breaks in every
other clone. Use plain `ln -s`, not `-f`: failing on an existing `CLAUDE.md` is
the point, it sends you back to step 1.

Then commit and PR as normal.

## Auditing every repo

Ask the default branch on the remote, not your checkout — working copies sit on
feature branches and go stale, which produces a to-do list of repos that were
already fixed.

Mode `120000` proves only that `CLAUDE.md` is *a* symlink, not that it points
at `AGENTS.md` — a wrong or broken target must still print `OK` if you check
mode alone. Read the tree entry's blob (the link target is the blob content)
and require the exact target `AGENTS.md` plus a regular `AGENTS.md` (`100644`)
before reporting `OK`.

```bash
for R in $(gh repo list "$OWNER" --limit 100 --source --no-archived \
             --json nameWithOwner --jq '.[].nameWithOwner'); do
  B=$(gh api repos/$R --jq .default_branch 2>/dev/null) || continue
  printf '%-40s ' "$R"
  JSON=$(gh api repos/$R/git/trees/$B 2>/dev/null) || { echo "-"; continue; }
  CLAUDE_MODE=$(jq -r '.tree[]|select(.path=="CLAUDE.md")|.mode' <<<"$JSON")
  CLAUDE_SHA=$(jq -r '.tree[]|select(.path=="CLAUDE.md")|.sha' <<<"$JSON")
  AGENTS_MODE=$(jq -r '.tree[]|select(.path=="AGENTS.md")|.mode' <<<"$JSON")
  if [ "$CLAUDE_MODE" = "120000" ]; then
    TARGET=$(gh api repos/$R/git/blobs/$CLAUDE_SHA --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    if [ "$TARGET" = "AGENTS.md" ] && [ "$AGENTS_MODE" = "100644" ]; then
      echo "OK"
    else
      echo "broken symlink -> ${TARGET:-?}"
    fi
  elif [ -n "$CLAUDE_MODE" ] && [ -n "$AGENTS_MODE" ]; then
    echo "both"
  elif [ -n "$CLAUDE_MODE" ]; then
    echo "migrate"
  elif [ -n "$AGENTS_MODE" ]; then
    echo "link"
  else
    echo "-"
  fi
done
```

## Gotchas

- **The contents API misreports symlinks.** GitHub resolves same-repo links, so
  `contents/CLAUDE.md` returns `type: "file"` with the *target's* size — a
  correct repo looks identical to a duplicated one. `type: "symlink"` appears
  only when the target is outside the repo, i.e. the broken case. Check the
  mode via `git/trees/$B` instead.
- **`core.symlinks=false`** (Windows, or a clone made with it) checks the link
  out as a small text file containing `AGENTS.md`, and git still reports the
  tree **clean** — agents read the stub and get no instructions, with nothing
  visibly wrong. Fix the clone, never re-commit the file. Repos with Windows
  contributors are a poor fit for this whole approach.
- **The contents API can't create the symlink** either (writes `100644` only).
  Without a clone you'd need `git/trees` with mode `120000` and the target as
  blob content — usually not worth it; just clone.
