#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[vast-bootstrap] %s\n' "$*"
}

require_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "This bootstrap currently supports Debian/Ubuntu hosts with apt-get."
    exit 1
  fi
}

install_packages() {
  local pkgs=(
    ca-certificates
    curl
    fd-find
    gh
    git
    neovim
    ripgrep
    tmux
  )

  log "Installing remote baseline packages..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"

  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sf /usr/bin/fdfind /usr/local/bin/fd
  fi
}

install_codex() {
  if [ ! -x "$HOME/.codex/packages/standalone/current/codex" ]; then
    log "Installing standalone Codex..."
    curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/codex-install.sh
    printf 'n\n' | sh /tmp/codex-install.sh
  fi

  if [ -x "$HOME/.codex/packages/standalone/current/codex" ]; then
    ln -sf "$HOME/.codex/packages/standalone/current/codex" /usr/local/bin/codex
  elif ! command -v codex >/dev/null 2>&1; then
    log "Codex install did not produce a usable binary."
    exit 1
  fi
}

start_codex_app_server() {
  log "Starting Codex app-server daemon..."
  codex app-server daemon bootstrap --remote-control
  codex app-server daemon start
  codex app-server daemon version
}

main() {
  require_apt
  touch "$HOME/.no_auto_tmux"
  install_packages
  install_codex
  start_codex_app_server
  log "Done."
}

main "$@"
