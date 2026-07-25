---
name: private-repo-standards
description: Use when applying branch-protection-equivalent standards to a private GitHub repo on a Free plan, where rulesets, branch protection, and CODEOWNERS all return 403 "Upgrade to GitHub Pro". Sets the merge settings that are free, installs a PR-only guard workflow and a local pre-push hook, and reports honestly what cannot be enforced. For public repos (or any repo on Pro), use repo-standards instead.
---

# Private repo standards (Free-plan fallback)

On a **private** repo under GitHub Free, the entire server-side governance stack
is unavailable:

| Feature | Private + Free |
|---|---|
| Rulesets (`repos/{r}/rulesets`) | 403 — needs Pro |
| Classic branch protection | 403 — needs Pro |
| CODEOWNERS (review auto-request) | inert — needs Pro |

So this is not a variant of `repo-standards`; it's a different, weaker toolkit.
Be honest with the user about that — the goal is the closest achievable
equivalent, plus a clear statement of the gap.

Confirm the situation before doing anything else:

```bash
R=owner/repo
gh api repos/$R --jq '{private,default_branch}'
gh api repos/$R/rulesets   # expect 403 Upgrade to GitHub Pro
```

If rulesets *do* work, this is the wrong skill — use **repo-standards**.

## What you actually get

| Layer | Enforcement strength |
|---|---|
| 1. Repo merge settings | Real, server-side. Squash-only, auto-delete branches. |
| 2. `main-guard` workflow | Detects a direct push after the fact; can't block it. |
| 3. Local `pre-push` hook | Real prevention — but only on this machine, and `--no-verify` skips it. |
| 4. CODEOWNERS file | Inert today; activates the moment the repo goes public or hits Pro. |

Nothing here stops a determined push to the default branch. Layer 3 stops the
accidental one, which is the realistic failure mode for a solo maintainer, and
layer 2 makes any bypass visible instead of silent.

## Step 1 — merge settings (free, server-side)

Mirrors the public standard's squash-only linear history:

```bash
gh api repos/$R -X PATCH \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true
```

Verify:

```bash
gh api repos/$R --jq '{allow_squash_merge,allow_merge_commit,allow_rebase_merge,delete_branch_on_merge}'
```

## Step 2 — the PR-only guard workflow

`assets/main-guard.yml` (next to this file) fails CI when a commit lands on the
default branch without coming from a merged PR. It cannot reject the push —
Actions runs after the fact — but it turns the commit red and is visible in the
Actions tab and in notifications.

Install it on a branch and open a PR, same as any change:

```bash
BASE=$(gh api repos/$R --jq .default_branch)
SHA=$(gh api repos/$R/git/ref/heads/$BASE --jq .object.sha)
gh api repos/$R/git/refs -X POST -f ref=refs/heads/chore/main-guard -f sha="$SHA"

BODY=$(base64 < assets/main-guard.yml | tr -d '\n')
gh api repos/$R/contents/.github/workflows/main-guard.yml -X PUT \
  -f message='ci: flag direct pushes to the default branch' \
  -f branch=chore/main-guard \
  -f content="$BODY"

gh pr create --repo $R --base "$BASE" --head chore/main-guard \
  --title 'ci: flag direct pushes to the default branch' \
  --body 'Fails when a commit reaches the default branch outside a merged PR. Advisory — Actions cannot block a push.'
```

Tell the user about the two known false positives before installing:

- The **first** run on a repo whose history predates the workflow.
- Legitimate bot pushes straight to the default branch (release tagging,
  `stefanzweifel/git-auto-commit`, etc.). If the repo has one, add its actor to
  the `ALLOWED_ACTORS` env in the workflow rather than deleting the guard.

Private repos on Free include 2,000 Actions minutes/month; this job is a few
seconds.

## Step 3 — the local pre-push hook

The only layer that actually prevents anything. `assets/pre-push` refuses a push
whose target ref is the default branch.

```bash
cd /path/to/clone
cp <this-skill-dir>/assets/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

Point out to the user:

- It is **per-clone**, not per-repo — a fresh clone has no hook. To make it
  apply everywhere by default, install it into a template dir once:
  `git config --global init.templateDir ~/.git-templates` and place the hook at
  `~/.git-templates/hooks/pre-push`. This applies to repos cloned or `init`ed
  *after* that config, not existing clones.
- `git push --no-verify` skips it by design; that's the intentional escape
  hatch, not a defect.

## Step 4 — CODEOWNERS anyway (optional, inert)

Committing `.github/CODEOWNERS` with `* @owner` does nothing on Free+private,
but costs nothing and starts working the instant the repo goes public or the
account hits Pro. Use the same PR flow as **repo-standards** Step 2. Say plainly
that it is inert for now, so the user isn't misled into thinking review is
enforced.

## Step 5 — report the gap

Close by stating what is *not* enforced, explicitly:

- No required approval, no required code-owner review.
- No required status checks — CI can be red and the merge still goes through.
- No block on force-push or deletion of the default branch.
- Direct pushes are flagged after the fact, not prevented server-side.

If the user wants these, the options are: make the repo public (then use
**repo-standards** as-is), or upgrade to GitHub Pro (which unlocks rulesets on
private repos, after which **repo-standards** applies unchanged). Present the
trade-off; don't push either.
