#!/bin/sh
# Codex notify hook: forward turn completion to the shared notifier.
# Codex appends one JSON payload to the command configured in config.toml.

if [ "$#" -ne 1 ]; then
  printf 'usage: %s JSON_PAYLOAD\n' "$0" >&2
  exit 64
fi

if ! printf '%s' "$1" | jq -e '.type == "agent-turn-complete"' >/dev/null; then
  printf 'unexpected Codex notification payload\n' >&2
  exit 65
fi

printf '%s' "$1" | "$HOME/.claude/tmux-notify.sh" stop codex
