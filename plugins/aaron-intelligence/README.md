# aaron-intelligence

Aaron's personal Claude Code enhancements — a growing bundle of hooks, skills,
and commands tuned to how he works. Each component is independent and documented
in its own section below; new ones get added over time.

## Components

| # | Component | Type | What it does |
|---|---|---|---|
| 1 | Bash tool guard | `PreToolUse` hook | Keeps Claude using Read/Edit/Write instead of the shell. |
| 2 | grill-me | skill | Interviews you relentlessly about a plan/design until it's fully resolved. |
| 3 | grill-me-issue | skill | Same interview, but writes the resolved plan up as a GitHub issue. |
| 4 | repo-standards | skill | One canonical branch ruleset + sole CODEOWNER, applied via `gh`. Public repos. |
| 5 | private-repo-standards | skill | Best-effort equivalent for private repos on GitHub Free, where rulesets are Pro-gated. |

---

## 1. Bash tool guard

Keeps Claude Code using its own file tools instead of the shell.

Anthropic's Bash tool guidance is explicit:

> Avoid using this tool to run `cat`, `head`, `tail`, `sed`, `awk`, or `echo`
> commands ... Instead, use the appropriate dedicated tool.

Claude reaches for the shell anyway often enough that it's a documented failure
mode (anthropics/claude-code issues [#21697](https://github.com/anthropics/claude-code/issues/21697),
[#31292](https://github.com/anthropics/claude-code/issues/31292) — note that
`disallowedTools: [Edit]` is trivially bypassed via `sed`/`awk`/redirects). This
plugin closes that gap with a `PreToolUse` hook on `Bash`.

## What it does

When a Bash command is clearly a stand-in for a file tool, the hook returns a
`deny` decision with an instructive reason. A `deny` is **soft**: the command
never runs, no user prompt appears, and the reason is fed back to Claude, which
re-plans with the right tool. Nothing is deleted or overwritten.

**Blocked → recommended tool:**

| Bash pattern | Use instead |
|---|---|
| `cat` / `head` / `tail` / `less` / `more` `<file>` (no pipe) | **Read** |
| `sed -i` / `perl -i` (in-place edit) | **Edit** |
| `echo` / `printf` / `cat` / `tee` `... > file` / `>> file` | **Write** (new) or **Edit** (change) |

## What it deliberately leaves alone

The hook is tuned for **precision over recall** — it would rather miss a
substitution than wedge legitimate shell work. These all pass through:

- Anything in a **pipeline** (`cat access.log | grep 500`) — Read/Edit can't stream.
- `tail -f` / `tail -F` — a live follow.
- `echo` to **stdout** (no redirect) — status/debug output.
- Standalone **`awk` / `sed`** data processing and transforms.
- **`grep` / `find`** — commonly legitimate; the Grep/Glob tools are preferred but not forced.
- **Program output** captured to a file (`npm test > results.txt`) — genuinely shell-only.
- Redirect/pipe operators that only appear **inside quoted strings** (`echo "use a > b"`).

## Config

- **Off switch:** set `AARON_INTELLIGENCE_GUARD=off` to disable the guard for the
  session. Any denial message also reminds Claude of this escape hatch.
- **Fail-open:** malformed input, oversized payloads, or any internal error →
  the command is allowed. A guard that denies on its own bugs is worse than none.

---

## 2. grill-me

A `/grill-me`-style skill that interviews you relentlessly about a plan or
design until every branch of the decision tree is resolved — one question at
a time, with a recommended answer offered for each, and codebase exploration
preferred over asking when a question can be answered that way.

Vendored (point-in-time copy, not a live mirror) from
[`mattpocock/skills`](https://github.com/mattpocock/skills)'s
`skills/productivity/grill-me/SKILL.md`.

## 3. grill-me-issue

Same interview process as **grill-me**, but instead of stopping once the plan
is resolved, it writes the outcome up as a well-structured GitHub issue
(problem, context, proposed approach, acceptance criteria, etc.) and shows it
to you for review. It never runs `gh issue create` on its own — filing is a
visible, shared-state action and requires your explicit go-ahead.

---

## 4. repo-standards

Puts every repo's default branch under one identical ruleset and names you as
sole code owner. Managed through the `gh` CLI.

The standard lives in `skills/repo-standards/standard.json` — it's the actual API
payload, piped through `jq` into `gh api --input -`, so the rules can't drift
between what's documented and what's applied.

**What it enforces:** no deletion or force-push of the default branch; PR
required with 1 approving review and code-owner review; stale reviews dismissed
on push; last-push approval; review threads resolved; squash-only merges; and
required status checks discovered per repo.

**Two things worth understanding:**

- **The admin bypass is load-bearing.** With one maintainer, a required approval
  can never be satisfied — you can't approve your own PR — so you merge via the
  repo-admin bypass. The rules still bind against everything that *isn't* an
  admin: the Actions `GITHUB_TOKEN`, Dependabot, GitHub Apps, a fine-grained PAT
  with `contents:write`, and any future collaborator. The skill refuses to apply
  a payload that drops that bypass actor, since doing so locks you out of merging
  with no self-service recovery.
- **Status checks are never guessed.** A required check that never reports blocks
  every PR on that repo permanently. The skill reads what actually ran, proposes
  only the CI check, and omits the rule entirely rather than guessing — deploy,
  release, and preview-deploy contexts are explicitly excluded.

Ordering matters: the CODEOWNERS PR merges *first*. Applying
`require_code_owner_review: true` to a repo with no CODEOWNERS file means no
owner exists to satisfy it.

Excluded on purpose: `required_signatures` (unsigned local commits would be
rejected), strict up-to-date branches (rebase churn), and
`required_linear_history` (squash-only already covers it).

---

## 5. private-repo-standards

On a **private** repo under GitHub Free, rulesets, classic branch protection, and
CODEOWNERS all return `403 Upgrade to GitHub Pro`. The whole server-side stack is
unavailable, so this is a separate, weaker toolkit rather than a variant of #4.

| Layer | Enforcement |
|---|---|
| Merge settings (`gh api -X PATCH`) | Real. Squash-only, auto-delete branches. |
| `assets/main-guard.yml` | Flags a direct push *after* the fact; can't block it. |
| `assets/pre-push` | Real prevention — this machine only; `--no-verify` skips it. |
| CODEOWNERS file | Inert until the repo goes public or hits Pro. |

The skill is required to close by stating plainly what is *not* enforced, so a
private repo never looks more protected than it is.

## Install

```
/plugin marketplace add ajustinjames/aaron-intelligence
/plugin install aaron-intelligence@aaron-intelligence
```

## Development

No build step. Verify changes directly:

```
node --check plugins/aaron-intelligence/hooks/bash-tool-guard.js
node --test  plugins/aaron-intelligence/hooks/bash-tool-guard.test.js

# skill assets
sh -n plugins/aaron-intelligence/skills/private-repo-standards/assets/pre-push
python3 -c "import yaml;yaml.safe_load(open('plugins/aaron-intelligence/skills/private-repo-standards/assets/main-guard.yml'))"
jq -e '.bypass_actors[]|select(.actor_type=="RepositoryRole" and .bypass_mode=="always")' \
  plugins/aaron-intelligence/skills/repo-standards/standard.json
```

Or drive the hook by hand with a synthetic payload:

```
echo '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}' \
  | node plugins/aaron-intelligence/hooks/bash-tool-guard.js
```
