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
          "ORCHESTRATOR MODE (pilotfish): you are the main session. Delegate " +
          "execution — don't run scout/executor work inline. Route to the " +
          "CHEAPEST role that can plausibly succeed: scout/Explore (haiku) for " +
          "recon, mech-executor (sonnet) for mechanical/fully-specified work, " +
          "executor (opus) only for real design judgment, verifier before " +
          "reporting non-trivial work done, security-executor for anything " +
          "security. Keep planning, architecture, ambiguity resolution, and " +
          "final review for yourself."
      }
    }));
  } catch (e) {
    // Silent fail — never block a user prompt.
  }
});
