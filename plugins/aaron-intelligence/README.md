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
```

Or drive the hook by hand with a synthetic payload:

```
echo '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}' \
  | node plugins/aaron-intelligence/hooks/bash-tool-guard.js
```
