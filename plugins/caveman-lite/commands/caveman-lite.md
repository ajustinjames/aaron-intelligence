---
description: Switch caveman-lite intensity level (lite/full/ultra/wenyan/off)
argument-hint: '[off|lite|full|ultra|wenyan|wenyan-lite|wenyan-ultra]'
disable-model-invocation: true
allowed-tools: Bash(node:*)
---

<!--
  Security note: `$ARGUMENTS` is interpolated into this shell line WITHOUT
  shell-escaping by Claude Code (upstream bug anthropics/claude-code#16163),
  so a hostile argument string could break out of the quotes. Two things
  contain the risk: this command is gated human-only via
  `disable-model-invocation: true` in the frontmatter (the model cannot invoke
  it, so a prompt-injected model can't feed it a payload), and the set-mode
  script whitelist-validates the argument against VALID_MODES and ignores
  anything else. Still: only type or paste a trusted mode token as the
  argument. Do not paste an untrusted string here. If upstream #16163 is fixed
  (proper escaping), this note can be relaxed.
-->
!`node "${CLAUDE_PLUGIN_ROOT}/hooks/caveman-set-mode.js" "$ARGUMENTS"`

Acknowledge the mode change in one short line, then apply it: if a level other than off was set, respond in that caveman register for the rest of the conversation (drop articles/filler/pleasantries/hedging, keep code/technical content exact). If off, respond normally.
