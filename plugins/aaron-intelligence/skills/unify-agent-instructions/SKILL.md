---
name: unify-agent-instructions
description: Use when making AGENTS.md the canonical agent-instructions file in a repo and CLAUDE.md a symlink to it — migrating an existing CLAUDE.md, setting up a new repo, or auditing which repos still have a standalone or duplicate CLAUDE.md.
---

# AGENTS.md canonical, CLAUDE.md a symlink

One instructions file per repo. `AGENTS.md` holds the content; `CLAUDE.md` is a
git-tracked symlink to it (mode `120000`).

`AGENTS.md` is the cross-tool convention and Claude Code follows the symlink, so
every tool reads the same file. Two real files drift, and each tool silently
reads different rules — that's the thing being prevented.

## 1. Classify

```bash
git pull --ff-only                    # classify current state, not a stale one
git ls-files -s AGENTS.md CLAUDE.md   # 100644 = file, 120000 = symlink
```

| State | Do |
|---|---|
| `CLAUDE.md` only | `git mv CLAUDE.md AGENTS.md`, then link |
| `AGENTS.md` only | link |
| `CLAUDE.md` already `120000` | done |
| Both exist, `CLAUDE.md` is a **stub** | `git rm CLAUDE.md`, then link |
| Both exist, both real | **stop** — `diff` them, user merges into `AGENTS.md` first |
| `CLAUDE.md` links elsewhere | **stop** — report the target |

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

```bash
for R in $(gh repo list "$OWNER" --limit 100 --source --no-archived \
             --json nameWithOwner --jq '.[].nameWithOwner'); do
  B=$(gh api repos/$R --jq .default_branch 2>/dev/null) || continue
  printf '%-40s ' "$R"
  gh api repos/$R/git/trees/$B \
    --jq '[.tree[]|select(.path=="AGENTS.md" or .path=="CLAUDE.md")|"\(.path):\(.mode):\(.size)"]|join(" ")' 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++){split($i,f,":"); m[f[1]]=f[2]; s[f[1]]=f[3]}
      if(m["CLAUDE.md"]=="120000") print "OK";
      else if(m["CLAUDE.md"] && m["AGENTS.md"]) printf "both (CLAUDE.md %sB)\n", s["CLAUDE.md"];
      else if(m["CLAUDE.md"]) print "migrate";
      else if(m["AGENTS.md"]) print "link";
      else print "-"}'
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
