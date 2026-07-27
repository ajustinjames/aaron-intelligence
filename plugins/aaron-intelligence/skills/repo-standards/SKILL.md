---
name: repo-standards
description: Use when standardizing GitHub branch protection on a public repo (or any repo on GitHub Pro) — applying the canonical default-branch ruleset, adding the owner as sole CODEOWNER, auditing which repos have drifted, or answering "are my branch rules set up right". Manages rulesets through the gh CLI against standard.json. For private repos on a Free plan, where rulesets return 403, use private-repo-standards instead.
---

# Repo standards (branch ruleset + sole CODEOWNER)

Brings a repo's default branch under one ruleset, identical everywhere, and
names the owner as sole code owner.

`standard.json` (next to this file) **is the standard.** Send it to the API
directly — never retype its values into an ad-hoc payload, and never hand-write
a ruleset body. If the table below ever disagrees with `standard.json`, the JSON
is right and the table is stale.

## What the standard enforces

| Rule | Value | Why |
|---|---|---|
| `deletion`, `non_fast_forward` | on | No deleting or force-pushing the default branch. |
| `required_approving_review_count` | 1 | Owner's explicit choice. |
| `require_code_owner_review` | true | Pairs with the CODEOWNERS file below. |
| `require_last_push_approval` | true | A push after approval re-opens review. |
| `dismiss_stale_reviews_on_push` | true | Blocks approve-then-append-code. |
| `required_review_thread_resolution` | true | No merging over unresolved comments. |
| `allowed_merge_methods` | `["squash"]` | Linear history. |
| `required_status_checks` | per repo — see below | CI must be green. |
| `bypass_actors` | repo admin, `always` | **Load-bearing.** See next section. |
| `delete_branch_on_merge` | true | Keeps merged PR branches from piling up. Repo setting, not a ruleset rule — see Step 5. |

Target is `~DEFAULT_BRANCH`, so it works on `main` and `master` repos alike.

### Why an admin bypass is not a hole

With one maintainer, a required approval can never be satisfied — you can't
approve your own PR — so the owner merges via the admin bypass. That is
expected, and it does not make the rules decorative: bypass is scoped to the
**admin role**, and these actors are not admins —

- the Actions `GITHUB_TOKEN`, Dependabot, and any GitHub App
- a fine-grained PAT with `contents:write` but not admin
- any future collaborator

Every rule above binds against all of them. That is the security this buys.

**Hard rule: never apply a payload whose `bypass_actors` lacks a
`RepositoryRole` actor with `bypass_mode: always`.** Removing it locks the owner
out of merging permanently, with no self-service recovery. Before any write,
confirm that actor is present in the body you are about to send; if it isn't,
stop and say so.

## Order of operations

1. **CODEOWNERS PR first**, and merged, before applying the ruleset.
2. Then the ruleset.

Backwards, and `require_code_owner_review: true` lands on a repo with no
CODEOWNERS file — no owner exists to satisfy the rule, so PRs are unmergeable
except by bypass.

Worth auditing for, because it's invisible: the ruleset shows green in the UI
while the code-owner rule does nothing. Check both halves together —

```bash
gh api repos/$R/rulesets --jq '.[]|select(.target=="branch")|.id' \
  | while read -r id; do
      gh api "repos/$R/rulesets/$id?includes_parents=false" \
        --jq 'select(.rules[]?.parameters.require_code_owner_review==true)|"requires code-owner review"'
    done
gh api repos/$R/contents/.github/CODEOWNERS --jq .path 2>/dev/null || echo "no CODEOWNERS"
```

## Step 1 — check eligibility

```bash
R=owner/repo
gh api repos/$R --jq '{private,default_branch}'
```

If `private: true` and `gh api repos/$R/rulesets` returns
`403 Upgrade to GitHub Pro`, stop — rulesets, branch protection, and CODEOWNERS
are all Pro-gated on private repos. Switch to the **private-repo-standards**
skill and report the repo as skipped.

## Step 2 — the CODEOWNERS PR

No clone needed; create the branch and blob through the API.

```bash
R=owner/repo
OWNER=$(gh api user --jq .login)
BASE=$(gh api repos/$R --jq .default_branch)
SHA=$(gh api repos/$R/git/ref/heads/$BASE --jq .object.sha)

gh api repos/$R/git/refs -X POST \
  -f ref=refs/heads/chore/codeowners -f sha="$SHA"

BODY=$(printf '# Sole owner of this repository.\n\n*       @%s\n' "$OWNER" \
         | base64 | tr -d '\n')
gh api repos/$R/contents/.github/CODEOWNERS -X PUT \
  -f message='chore: add CODEOWNERS naming sole owner' \
  -f branch=chore/codeowners \
  -f content="$BODY"

gh pr create --repo $R --base "$BASE" --head chore/codeowners \
  --title 'chore: add CODEOWNERS naming sole owner' \
  --body "Names @$OWNER owner of all paths. Required before the branch ruleset can enforce require_code_owner_review."
```

Notes:

- Put the file at `.github/CODEOWNERS`. GitHub also honors root and `docs/`,
  but pick one location and keep it consistent.
- `* @owner` is the whole file — one pattern, one owner.
- Idempotency: check `gh api repos/$R/contents/.github/CODEOWNERS --jq .path`
  first and skip if it already matches. If the branch already exists, reuse it
  (the `POST /git/refs` returns "already exists"); if a PR is already open from
  it, `gh pr list --repo $R --head chore/codeowners` finds it — don't stack
  duplicates.
- Updating an existing file needs its blob sha: add
  `-f sha=$(gh api "repos/$R/contents/.github/CODEOWNERS?ref=chore/codeowners" --jq .sha)`.

## Step 3 — pick the status checks (the dangerous part)

**A required context that never reports blocks every PR on that repo forever.**
Never guess a check name, and never copy one repo's checks to another.

See what actually reports:

```bash
gh api repos/$R/commits/HEAD/check-runs --jq '.check_runs[]|"\(.name)\t\(.app.slug)/\(.app.id)"' | sort -u
gh api repos/$R/actions/workflows --jq '.workflows[]|"\(.name) [\(.state)] \(.path)"'
```

Then judge, and **show the user your picks before applying**:

- Require the CI/test/lint check — the one that runs on every PR.
- Do **not** require deploy or release checks (`deploy`, `release`,
  `Cloudflare Pages`, `pages-build-deployment`). They're typically
  default-branch-only or slow and flaky; requiring them deadlocks PRs.
- Do **not** require `Dependabot`.
- If a workflow exists but no check from it appeared on `HEAD`, its context name
  is unconfirmed — **omit status checks entirely for that repo** rather than
  guessing. A ruleset with no CI gate is recoverable; a wrong one isn't.

If a required check does wedge a repo, recover by removing the rule (Step 4 with
the `del` form) or merging once via admin bypass.

## Step 4 — apply the ruleset

Find the existing ruleset (`includes_parents=false` keeps inherited org rules
out of the picture):

```bash
gh api repos/$R/rulesets --jq '.[]|select(.target=="branch")|"\(.id) \(.name)"'
ID=<id>
gh api "repos/$R/rulesets/$ID?includes_parents=false"   # the before state
```

**Show the user a before/after summary of the changed fields, then write.**
`PUT` to update, `POST` to create:

```bash
CHECKS='[{"context":"validate","integration_id":15368}]'   # 15368 = GitHub Actions

jq --argjson c "$CHECKS" \
  '(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks) |= $c' \
  standard.json \
  | gh api "repos/$R/rulesets/$ID" -X PUT --input -
```

With no trustworthy check, drop the rule rather than sending an empty list:

```bash
jq 'del(.rules[]|select(.type=="required_status_checks"))' standard.json \
  | gh api "repos/$R/rulesets/$ID" -X PUT --input -
```

Creating from scratch is the same body to `POST repos/$R/rulesets`.

If a repo has more than one branch ruleset, don't guess which to update — the
standard's name is `default`; report the extras and let the user consolidate.
Renaming a drifted ruleset (`Default`, `Main branch protections`) is just the
`name` field in the `PUT`; the id and history are preserved.

## Step 5 — enable delete-branch-on-merge

Not part of the ruleset — it's a plain repo setting, so it's its own API call:

```bash
gh api repos/$R --jq .delete_branch_on_merge   # before state
gh api repos/$R -X PATCH -f delete_branch_on_merge=true --jq '{delete_branch_on_merge}'
```

Idempotent — safe to run even if already `true`.

## Auditing several repos

```bash
for R in $(gh repo list "$OWNER" --limit 100 --source --no-archived \
             --json nameWithOwner --jq '.[].nameWithOwner'); do
  echo "== $R"
  gh api repos/$R/rulesets --jq '.[]|select(.target=="branch")|"  \(.id) \(.name)"' 2>&1 \
    | sed 's/.*Upgrade to GitHub Pro.*/  SKIP private repo (needs Pro)/'
  gh api repos/$R --jq '"  delete_branch_on_merge: \(.delete_branch_on_merge)"'
done
```

Apply one repo at a time. Status checks differ per repo, so a blind fan-out is
exactly how a wrong context gets applied somewhere it doesn't run.

## Deliberately excluded

- **`required_signatures`** — the owner's local commits are unsigned (only
  web-UI merges show verified), so this would reject every `git push`. Revisit
  only after commit signing is configured locally.
- **`strict_required_status_checks_policy: true`** (branch must be up to date
  before merging) — constant rebase churn on a solo repo for little gain.
- **`required_linear_history`** — redundant; squash-only merges already give it.
