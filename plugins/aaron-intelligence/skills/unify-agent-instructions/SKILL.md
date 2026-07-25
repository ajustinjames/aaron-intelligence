---
name: unify-agent-instructions
description: Use when making AGENTS.md the canonical agent-instructions file in a repo and CLAUDE.md a symlink to it — migrating an existing CLAUDE.md, setting up a new repo, auditing which repos still have a standalone CLAUDE.md, or answering "why are my agent instructions duplicated". Covers the both-files-exist conflict and the core.symlinks trap.
---

# AGENTS.md canonical, CLAUDE.md a symlink

One file of agent instructions per repo. `AGENTS.md` holds the content;
`CLAUDE.md` is a git-tracked symlink pointing at it.

Why this direction: `AGENTS.md` is the cross-tool convention (Codex, Cursor,
Copilot, Gemini CLI, Zed all read it), and Claude Code follows a `CLAUDE.md`
symlink transparently. Canonical content sits under the name every tool knows,
and Claude Code still finds it. The reverse — `AGENTS.md` as the link — works
identically for Claude but reads backwards to everything else.

**Never let both exist as real files.** Two files drift, and each tool silently
reads a different set of rules. That is the whole problem this solves.

## Step 1 — classify the repo

Run at the repo root. Do not skip this; the right action depends entirely on
which state you're in, and two of the states must not be auto-fixed.

```bash
git rev-parse --show-toplevel                    # confirm you're at the root
git ls-files -s AGENTS.md CLAUDE.md              # index modes: 100644=file 120000=symlink
ls -la AGENTS.md CLAUDE.md 2>&1                  # what's actually on disk
readlink CLAUDE.md 2>/dev/null                   # link target, if any
git check-ignore -v AGENTS.md CLAUDE.md          # ignored? see Gotchas
```

| # | State | Action |
|---|---|---|
| A | Neither file exists | Nothing to migrate. Write `AGENTS.md` first, then Step 2b. |
| B | `CLAUDE.md` only, regular file | **Step 2a** — the common migration. |
| C | `AGENTS.md` only | **Step 2b** — just add the link. |
| D | `CLAUDE.md` is `120000` → `AGENTS.md` | Already correct. Verify (Step 3) and stop. |
| E | Both real files, **identical** content | **Step 2c** — drop the duplicate, link. |
| F | Both real files, **different** content | **Stop.** See below. |
| G | `CLAUDE.md` symlinks somewhere *else* | **Stop.** Report the target; deliberate, don't clobber. |
| H | Index says `120000`, disk says regular file | `core.symlinks` trap — see Gotchas. |
| I | `CLAUDE.md` is a **pointer stub** at AGENTS.md | **Step 2c** — upgrade it to a real symlink. |

### State I — the pointer stub (check this before calling it F)

By far the most common "both files exist" case in practice. `CLAUDE.md` isn't a
second set of rules, it's a hand-rolled redirect — the same intent as the
symlink, implemented in prose. Seen in the wild:

```
@AGENTS.md
```

```markdown
# CLAUDE.md

Claude Code should read and follow the shared repository instructions in `AGENTS.md`.
```

Both are safe to replace with a real symlink (Step 2c) — nothing is lost, and
the stub's weaknesses go away: an `@import` costs an extra file read and is
Claude-only, and prose redirects get ignored under a strong task prompt. One of
these turned up pointing at an **absolute** path
(`/Users/you/workspace/repo/AGENTS.md`) — dead in every other clone and on CI.

**Read the stub before classifying.** If it carries even one rule that isn't in
`AGENTS.md` — a Claude-specific instruction, a tool note — it is state F, not
state I, and that rule has to be merged into `AGENTS.md` first.

### State F — both exist and differ

Not a stub, and both hold real content. Do not merge them yourself and do not
pick a winner. Show the user the diff and let them decide:

```bash
diff -u CLAUDE.md AGENTS.md
```

Each file may hold rules the other lacks, and a wrong merge silently changes how
every agent behaves in that repo. Once the user gives you merged content, write
it to `AGENTS.md`, then run Step 2c.

## Step 2 — apply

Always on a branch — these repos require PRs (see the **repo-standards** skill).

```bash
git checkout -b chore/unify-agent-instructions
```

### 2a. Migrate an existing CLAUDE.md (state B)

`git mv` first so rename detection keeps the file's history — `git log --follow
AGENTS.md` then still reaches back past the migration.

```bash
git mv CLAUDE.md AGENTS.md
ln -s AGENTS.md CLAUDE.md
git add CLAUDE.md
```

### 2b. AGENTS.md already canonical (state C)

```bash
ln -s AGENTS.md CLAUDE.md
git add CLAUDE.md
```

### 2c. Identical duplicates (state E, and state F after merging)

```bash
git rm -q CLAUDE.md
ln -s AGENTS.md CLAUDE.md
git add CLAUDE.md
```

The target is the bare relative name `AGENTS.md` — a sibling in the same
directory. Never an absolute path (`/Users/...`), which breaks in every other
clone and on CI.

## Step 3 — verify before committing

The index mode is the thing that matters. A `100644` here means you committed a
9-byte text file that merely *says* `AGENTS.md`, which no tool will follow:

```bash
git ls-files -s CLAUDE.md      # MUST be 120000
readlink CLAUDE.md             # MUST be exactly: AGENTS.md
head -1 CLAUDE.md              # reads through the link → AGENTS.md's first line
```

Then commit and PR:

```bash
git commit -m "chore: make AGENTS.md canonical, CLAUDE.md a symlink"
git push -u origin chore/unify-agent-instructions
gh pr create --title "chore: make AGENTS.md canonical, CLAUDE.md a symlink" \
  --body "AGENTS.md is now the single source of agent instructions; CLAUDE.md is a symlink to it, so Claude Code and every AGENTS.md-aware tool read the same file."
```

Confirm the symlink survived the round trip — GitHub shows a `120000` blob as a
link, and a fresh clone should get a real symlink:

```bash
gh api repos/$R/contents/CLAUDE.md --jq .type   # → "symlink"
```

## Auditing every repo

Local checkouts, since making a symlink needs a working tree:

```bash
for d in ~/workspace/*/ ~/workspace/*/*/; do
  [ -d "$d/.git" ] || continue
  printf '%-45s ' "${d#$HOME/}"
  git -C "$d" ls-files -s AGENTS.md CLAUDE.md 2>/dev/null \
    | awk '{m[$4]=$1} END{
        if (m["CLAUDE.md"]=="120000") print "OK";
        else if (m["CLAUDE.md"] && m["AGENTS.md"]) print "BOTH REAL - needs review";
        else if (m["CLAUDE.md"]) print "migrate (CLAUDE.md only)";
        else if (m["AGENTS.md"]) print "link (AGENTS.md only)";
        else print "-";
      }'
done
```

Fix one repo at a time. A `BOTH REAL` row is only a *candidate* for state F —
open `CLAUDE.md` before deciding, since most turn out to be state I stubs. A
quick first cut, since stubs are tiny:

```bash
git -C "$d" cat-file -s :CLAUDE.md    # under ~300B is almost always a stub
```

### Without a clone

The contents API only writes regular files (`100644`), so it **cannot** create
the symlink — that's why this skill is clone-based. To do it remotely you must
drop to the git trees API, which accepts mode `120000` with the target as blob
content:

```bash
R=owner/repo
BASE=$(gh api repos/$R --jq .default_branch)
SHA=$(gh api repos/$R/git/ref/heads/$BASE --jq .object.sha)
TREE=$(gh api repos/$R/git/commits/$SHA --jq .tree.sha)
BLOB=$(gh api "repos/$R/contents/CLAUDE.md?ref=$BASE" --jq .sha)   # state B only

# Reuse CLAUDE.md's existing blob as AGENTS.md (content never leaves GitHub),
# and replace CLAUDE.md with a symlink blob. Build the body with jq and send it
# via --input -; gh's -f flags cannot express an array of objects.
NEW=$(jq -n --arg base "$TREE" --arg blob "$BLOB" '{
    base_tree: $base,
    tree: [
      {path:"AGENTS.md", mode:"100644", type:"blob", sha:$blob},
      {path:"CLAUDE.md", mode:"120000", type:"blob", content:"AGENTS.md"}
    ]
  }' | gh api repos/$R/git/trees --input - --jq .sha)

COMMIT=$(jq -n --arg tree "$NEW" --arg parent "$SHA" '{
    tree: $tree, parents: [$parent],
    message: "chore: make AGENTS.md canonical, CLAUDE.md a symlink"
  }' | gh api repos/$R/git/commits --input - --jq .sha)
gh api repos/$R/git/refs -X POST -f ref=refs/heads/chore/unify-agent-instructions -f sha="$COMMIT"
gh pr create --repo $R --base "$BASE" --head chore/unify-agent-instructions \
  --title 'chore: make AGENTS.md canonical, CLAUDE.md a symlink' --body 'Single source of agent instructions.'
```

Verify with the `contents` check above — if it reports `file` rather than
`symlink`, the mode didn't take and the repo is now in state E or F.

## Gotchas

- **`core.symlinks=false` (state H).** On Windows, and on any clone made with
  that setting, git checks the link out as a regular file whose contents are the
  literal text `AGENTS.md` — and then reports the tree **clean**, because the
  index still says `120000`. Nothing looks wrong; agents just read a 9-byte file
  and get no instructions. Check with `git config --get core.symlinks`. Fix the
  clone (`git config core.symlinks true && git checkout -- CLAUDE.md`), never by
  re-committing the file. If a repo has Windows contributors, this whole approach
  is a poor fit — keep a real `CLAUDE.md` there instead.
- **Don't reach for `ln -sf` as a shortcut.** Plain `ln -s` fails loudly when
  `CLAUDE.md` exists, which is the correct outcome — it forces you back to Step 1
  to classify. `-f` clobbers, and if the existing `CLAUDE.md` is a symlink to a
  *directory* it creates the link *inside* that directory instead.
- **An ignored CLAUDE.md.** If `git check-ignore` matched, the symlink exists
  locally but is never committed, so no one else gets it. That's usually a
  deliberate "CLAUDE.md is personal, AGENTS.md is shared" split — surface it and
  ask before `git add -f`.
- **Subdirectory instruction files.** Claude Code reads nested `CLAUDE.md` files
  too. Same treatment per directory, and the target stays the bare sibling name
  `AGENTS.md` — relative to the link's own directory, not the repo root.
- **This plugin's own repo is the reference implementation:** `CLAUDE.md →
  AGENTS.md`, committed as `120000` since `5c4f54e`.
