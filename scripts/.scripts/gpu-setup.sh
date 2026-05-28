#!/usr/bin/env bash
#
# Set up a fresh Vast GPU host.
#
# Sequence:
# 1. Install the small baseline toolchain with apt.
# 2. Install uv.
# 3. Install the trustworthy-gradients deploy key from /tmp.
# 4. Install the dotfiles repo and link the portable configs.
# 5. Install standalone Codex and start its app-server daemon.
# 6. Clone or update filipviz/trustworthy-gradients.
# 7. Verify the expected commands, dotfiles, deploy key, repo, and Codex daemon.

set -euo pipefail

REPO_DIR="$HOME/trustworthy-gradients"
REPO_SSH="git@github-trustworthy-gradients:filipviz/trustworthy-gradients.git"
DEPLOY_KEY_DEST="$HOME/.ssh/trustworthy-gradients"
DOTFILES_DIR="$HOME/Developer/dotfiles"
DOTFILES_REPO="https://github.com/filipviz/dotfiles.git"
DOTFILES_ARCHIVE="${DOTFILES_ARCHIVE:-/tmp/dotfiles.tar.gz}"
REMOTE_DEPLOY_KEY="${REMOTE_DEPLOY_KEY:-/tmp/trustworthy-gradients.deploy-key}"

log() {
  printf '[gpu-setup] %s\n' "$*"
}

die() {
  printf '[gpu-setup] error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
  done
}

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    printf ''
  elif command -v sudo >/dev/null 2>&1; then
    printf 'sudo'
  else
    die "need root privileges or sudo"
  fi
}

install_packages() {
  local sudo
  sudo="$(sudo_cmd)"

  log "Installing apt packages..."
  $sudo apt-get update
  $sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    fd-find \
    fzf \
    git \
    lazygit \
    less \
    neovim \
    nnn \
    ripgrep \
    tmux

  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    $sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
  fi
}

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv already installed."
    return
  fi

  log "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"

  if [ -x "$HOME/.local/bin/uv" ]; then
    local sudo
    sudo="$(sudo_cmd)"
    $sudo ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv
  fi
}

install_codex() {
  export PATH="$HOME/.codex/bin:$HOME/.local/bin:$PATH"

  if [ ! -x "$HOME/.codex/packages/standalone/current/codex" ] && ! command -v codex >/dev/null 2>&1; then
    log "Installing Codex..."
    curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/codex-install.sh
    printf 'n\n' | sh /tmp/codex-install.sh
  fi

  local codex_bin=""
  if [ -x "$HOME/.codex/packages/standalone/current/codex" ]; then
    codex_bin="$HOME/.codex/packages/standalone/current/codex"
  elif codex_bin="$(command -v codex)"; then
    :
  else
    die "Codex install did not produce a usable binary"
  fi

  if [ -n "$codex_bin" ]; then
    local sudo
    sudo="$(sudo_cmd)"
    $sudo ln -sf "$codex_bin" /usr/local/bin/codex
  fi

  log "Starting Codex app server..."
  codex app-server daemon bootstrap --remote-control
  codex app-server daemon start
}

setup_deploy_key() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [ -s "$REMOTE_DEPLOY_KEY" ]; then
    install -m 600 "$REMOTE_DEPLOY_KEY" "$DEPLOY_KEY_DEST"
    rm -f "$REMOTE_DEPLOY_KEY"
  elif [ -s "$DEPLOY_KEY_DEST" ]; then
    chmod 600 "$DEPLOY_KEY_DEST"
  else
    die "missing deploy key; copy it to $REMOTE_DEPLOY_KEY"
  fi

  touch "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"

  if ! grep -q '^Host github-trustworthy-gradients$' "$HOME/.ssh/config"; then
    cat >>"$HOME/.ssh/config" <<'EOF'

Host github-trustworthy-gradients
  HostName github.com
  User git
  IdentityFile ~/.ssh/trustworthy-gradients
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
  fi
}

clone_repo() {
  if [ -d "$REPO_DIR/.git" ]; then
    log "Updating $REPO_DIR..."
    git -C "$REPO_DIR" fetch --all --prune
    git -C "$REPO_DIR" status --short --branch
  else
    log "Cloning trustworthy-gradients..."
    git clone "$REPO_SSH" "$REPO_DIR"
  fi
}

install_dotfiles_repo() {
  mkdir -p "$HOME/Developer"

  if [ -s "$DOTFILES_ARCHIVE" ]; then
    log "Extracting uploaded dotfiles..."
    tar -xzf "$DOTFILES_ARCHIVE" -C "$HOME/Developer"
    return
  fi

  if [ -d "$DOTFILES_DIR/.git" ]; then
    log "Updating dotfiles..."
    git -C "$DOTFILES_DIR" fetch --all --prune
    git -C "$DOTFILES_DIR" status --short --branch
  else
    log "Cloning dotfiles..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi
}

link_config() {
  local mode="$1"
  local src="$2"
  local dest="$3"
  local backup="${dest}.before-gpu-setup"

  case "$mode" in
    keep|replace)
      ;;
    *)
      die "unknown link mode: $mode"
      ;;
  esac

  if [ ! -e "$src" ]; then
    die "missing dotfiles path: $src"
  fi

  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ]; then
    ln -sfn "$src" "$dest"
    return
  fi

  if [ -e "$dest" ]; then
    if [ "$mode" = keep ]; then
      log "$dest already exists; leaving it unchanged."
      return
    fi

    if [ -e "$backup" ]; then
      die "$dest exists and $backup already exists; inspect before replacing"
    fi
    mv "$dest" "$backup"
    log "Moved existing $dest to $backup."
  fi

  ln -s "$src" "$dest"
}

link_dotfiles() {
  log "Linking portable dotfiles..."
  link_config keep "$DOTFILES_DIR/scripts/.scripts" "$HOME/.scripts"
  link_config replace "$DOTFILES_DIR/bash/.bashrc" "$HOME/.bashrc"
  link_config keep "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
  link_config keep "$DOTFILES_DIR/nvim/.config/nvim" "$HOME/.config/nvim"
  link_config keep "$DOTFILES_DIR/codex/.codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
}

verify_setup() {
  log "Verifying setup..."
  require_command tmux git lazygit nvim rg fd curl nnn fzf uv codex
  test -d "$DOTFILES_DIR/.git"
  test -d "$HOME/.scripts"
  test -x "$HOME/.scripts/gpu-setup.sh"
  test -L "$HOME/.bashrc"
  test -e "$HOME/.tmux.conf"
  test -e "$HOME/.config/nvim/init.lua"
  test -s "$HOME/.codex/AGENTS.md"
  test -s "$DEPLOY_KEY_DEST"
  test -d "$REPO_DIR/.git"
  codex app-server daemon version
}

main() {
  if ! command -v apt-get >/dev/null 2>&1; then
    die "this script currently supports Ubuntu/Debian hosts with apt-get"
  fi

  touch "$HOME/.no_auto_tmux"
  install_packages
  install_uv
  setup_deploy_key
  install_dotfiles_repo
  link_dotfiles
  install_codex
  clone_repo
  verify_setup
  log "Done."
}

main "$@"
