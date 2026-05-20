#!/usr/bin/env bash
set -euo pipefail

HOST_ALIAS="${1:-codex-gpu}"
LOCAL_AGENTS="${CODEX_AGENTS_FILE:-$HOME/.codex/AGENTS.md}"
GHOSTTY_TERMINFO="${GHOSTTY_TERMINFO:-/Applications/Ghostty.app/Contents/Resources/terminfo/78/xterm-ghostty}"

log() {
  printf '[vast-finalize] %s\n' "$*"
}

copy_global_agents() {
  if [ ! -s "$LOCAL_AGENTS" ]; then
    log "No local AGENTS.md found at $LOCAL_AGENTS; skipping."
    return
  fi

  log "Copying global Codex instructions..."
  ssh "$HOST_ALIAS" 'mkdir -p ~/.codex'
  scp "$LOCAL_AGENTS" "$HOST_ALIAS:~/.codex/AGENTS.md"
  ssh "$HOST_ALIAS" 'test -s ~/.codex/AGENTS.md'
}

copy_ghostty_terminfo() {
  if [ -f "$GHOSTTY_TERMINFO" ]; then
    log "Copying Ghostty terminfo..."
    ssh "$HOST_ALIAS" 'mkdir -p /usr/share/terminfo/x'
    scp "$GHOSTTY_TERMINFO" "$HOST_ALIAS:/usr/share/terminfo/x/xterm-ghostty"
  else
    log "Ghostty terminfo file not found at $GHOSTTY_TERMINFO; trying infocmp fallback."
    infocmp xterm-ghostty > /tmp/xterm-ghostty.terminfo
    scp /tmp/xterm-ghostty.terminfo "$HOST_ALIAS:/tmp/xterm-ghostty.terminfo"
    ssh "$HOST_ALIAS" 'tic -x -o /usr/share/terminfo /tmp/xterm-ghostty.terminfo'
  fi

  ssh "$HOST_ALIAS" 'infocmp xterm-ghostty >/dev/null'
}

verify_remote() {
  log "Verifying remote setup..."
  ssh "$HOST_ALIAS" '
    set -e
    hostname
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    codex app-server daemon version
    codex --version
    command -v rg
    command -v fd
    test -s ~/.codex/AGENTS.md
    infocmp xterm-ghostty >/dev/null
  '
}

main() {
  copy_global_agents
  copy_ghostty_terminfo
  verify_remote
  log "Done."
}

main "$@"
