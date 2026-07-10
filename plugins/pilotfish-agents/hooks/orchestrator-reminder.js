#!/usr/bin/env node
// pilotfish-agents — UserPromptSubmit hook
//
// Per-turn reinforcement of the orchestration policy. This is the fix for
// "pilotfish failed to trigger": the SessionStart policy (and any copy pasted
// into CLAUDE.md) is passive context that decays across a long session under a
// strongly-imperative task prompt. A short reminder re-injected every turn —
// the same mechanism the caveman-lite hook uses — keeps the main session from
// drifting back into inline execution or over-tiering.
//
// Targets both observed failure modes:
//   1. doing scout/executor work inline instead of delegating it
//   2. reaching for executor (opus) on mechanical work that is mech-executor
//      (sonnet) territory — i.e. skipping "start with the cheapest role"
//
// Fires only in the main session (UserPromptSubmit is a main-session event;
// subagent invocations don't raise it), matching the policy's scope.
//
// Off switch: set PILOTFISH_ORCHESTRATOR=off.

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    if ((process.env.PILOTFISH_ORCHESTRATOR || '').trim().toLowerCase() === 'off') {
      return;
    }
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext:
          "ORCHESTRATOR MODE (pilotfish). Bright-line rules — thresholds, not vibes:\n" +
          "- Locating or reading >3 files to answer a question → scout/Explore (haiku). Never inline.\n" +
          "- ≥5 similar edits, or any fully-specified change → mech-executor (sonnet).\n" +
          "- Implementation needing design judgment → executor (opus).\n" +
          "- The word 'security' applies → security-executor. No exceptions.\n" +
          "- Diff touches >50 lines or changes behavior → verifier BEFORE reporting done.\n" +
          "Keep for yourself: planning, architecture, ambiguity resolution, final review, " +
          "single-file reads you need immediately."
      }
    }));
  } catch (e) {
    // Silent fail — never block a user prompt.
  }
});
