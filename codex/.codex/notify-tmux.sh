#!/bin/sh
# Codex notify hook: forward turn-completion to the shared tmux/system
# notifier. Codex appends one JSON argument after any static args configured
# in notify (config.toml), so the payload is always the last argument.

json=""
for json; do :; done
case "$json" in
  *agent-turn-complete*)
    printf '%s' "$json" | sh "$HOME/.claude/tmux-notify.sh" stop codex
    ;;
esac
