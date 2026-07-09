---
description: Switch caveman-lite intensity level (lite/full/ultra/wenyan/off)
argument-hint: '[lite|full|ultra|wenyan|wenyan-lite|wenyan-ultra|off]'
disable-model-invocation: true
allowed-tools: Bash(node:*)
---

!`node "${CLAUDE_PLUGIN_ROOT}/hooks/caveman-set-mode.js" "$ARGUMENTS"`

Acknowledge the mode change in one short line, then apply it: if a level other than off was set, respond in that caveman register for the rest of the conversation (drop articles/filler/pleasantries/hedging, keep code/technical content exact). If off, respond normally.
