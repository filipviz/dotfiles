#!/bin/sh
# Codex notify hook: forward turn-completion to the shared tmux/system
# notifier. Codex invokes the configured notify program with one JSON argument.
case "${1:-}" in
  *agent-turn-complete*)
    sh "$HOME/.claude/tmux-notify.sh" stop codex </dev/null
    ;;
esac
