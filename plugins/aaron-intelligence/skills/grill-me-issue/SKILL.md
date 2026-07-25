---
name: grill-me-issue
description: Interview the user relentlessly about a plan or design until reaching shared understanding, then write up the result as a well-structured GitHub issue. Use when the user wants to stress-test a plan and turn it into a GitHub issue, mentions "grill me" with an issue/ticket in mind, or asks to be grilled before filing a bug/feature request.
---

<!--
Adapted from mattpocock/skills, commit 733d312884b3878a9a9cff693c5886943753a741
(skills/productivity/grill-me/SKILL.md) — same interview process, GitHub-issue
output stage appended. Point-in-time derivative, not a live mirror.
-->

Interview me relentlessly about every aspect of this plan or problem until we reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead of asking.

Keep going until every open branch is resolved — ambiguous scope, edge cases, acceptance criteria, and any explicit non-goals.

## Once the interview is resolved

Write up the outcome as a single well-structured GitHub issue in Markdown, using whatever sections fit the content (typically a subset of: Problem/Summary, Context, Proposed approach, Acceptance criteria, Out of scope, Open questions). Prefer a checklist for acceptance criteria. Keep it tight — no filler, no restating the whole interview transcript.

Show the drafted issue (title + body) to the user for review before doing anything with it. Do not run `gh issue create` (or otherwise file it) unless the user explicitly confirms — filing an issue is a visible, shared-state action.
