#!/usr/bin/env bash
#
# Set up a fresh GPU host.
#
# Sequence:
# 1. Install the small baseline toolchain with apt.
# 2. Install lazygit, fzf, delta, Neovim, tree-sitter, and uv.
# 3. Install the trustworthy-gradients deploy key from /tmp.
# 4. Install the dotfiles repo and link the portable configs.
# 5. Install standalone Codex and start its app-server daemon.
# 6. Install Claude Code.
# 7. Clone or update trustworthy-gradients, run uv sync, then start prepare.py in the background.
# 8. Verify commands, dotfiles, deploy key, repo, and the Codex daemon.

set -euo pipefail

UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-300}"

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

target_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s\n' "$1" ;;
    aarch64|arm64) printf '%s\n' "$2" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

latest_github_version() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" |
    sed -n 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' |
    head -n 1
}

# Download a release tarball and install a single binary from it. The third
# argument is the binary's path inside the archive when it isn't at the root.
install_release_binary() {
  local name="$1" url="$2" member="${3:-$1}"
  local tmpdir sudo
  tmpdir="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmpdir/archive.tar.gz"
  tar -xzf "$tmpdir/archive.tar.gz" -C "$tmpdir" "$member"
  sudo="$(sudo_cmd)"
  $sudo install -m 0755 "$tmpdir/$member" "/usr/local/bin/$name"
  rm -rf "$tmpdir"
}

install_packages() {
  local sudo
  sudo="$(sudo_cmd)"

  log "Installing apt packages..."
  $sudo apt-get update
  $sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bubblewrap \
    ca-certificates \
    curl \
    fd-find \
    git \
    jq \
    less \
    nnn \
    ripgrep \
    tar \
    tmux

  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    $sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
  fi
}

install_lazygit() {
  if command -v lazygit >/dev/null 2>&1; then
    log "lazygit already installed."
    return
  fi

  local arch version
  arch="$(target_arch x86_64 arm64)"
  version="$(latest_github_version jesseduffield/lazygit)"
  [ -n "$version" ] || die "could not determine latest lazygit version"

  log "Installing lazygit..."
  install_release_binary lazygit \
    "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${arch}.tar.gz"
}

install_delta() {
  if command -v delta >/dev/null 2>&1; then
    log "delta already installed."
    return
  fi

  local target version
  target="$(target_arch x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu)"
  version="$(latest_github_version dandavison/delta)"
  [ -n "$version" ] || die "could not determine latest delta version"

  log "Installing delta..."
  install_release_binary delta \
    "https://github.com/dandavison/delta/releases/download/${version}/delta-${version}-${target}.tar.gz" \
    "delta-${version}-${target}/delta"
}

fzf_is_modern() {
  local version
  version="$(fzf --version 2>/dev/null | awk '{print $1}')"
  [ -n "$version" ] || return 1
  [ "$(printf '%s\n' "0.36.0" "$version" | sort -V | tail -n 1)" = "$version" ]
}

install_fzf() {
  if command -v fzf >/dev/null 2>&1 && fzf_is_modern; then
    log "fzf already installed."
    return
  fi

  local arch version
  arch="$(target_arch amd64 arm64)"
  version="$(latest_github_version junegunn/fzf)"
  [ -n "$version" ] || die "could not determine latest fzf version"

  log "Installing fzf..."
  install_release_binary fzf \
    "https://github.com/junegunn/fzf/releases/download/v${version}/fzf-${version}-linux_${arch}.tar.gz"
}

install_neovim() {
  if command -v nvim >/dev/null 2>&1 &&
    nvim --clean --headless +'lua assert(vim.fn.has("nvim-0.11") == 1)' +qa >/dev/null 2>&1; then
    log "Neovim already installed."
    return
  fi

  local arch tmpdir sudo
  arch="$(target_arch x86_64 arm64)"

  log "Installing Neovim..."
  tmpdir="$(mktemp -d)"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${arch}.tar.gz" \
    -o "$tmpdir/nvim.tar.gz"

  sudo="$(sudo_cmd)"
  $sudo rm -rf "/opt/nvim-linux-${arch}"
  $sudo tar -xzf "$tmpdir/nvim.tar.gz" -C /opt
  $sudo chmod -R a+rX "/opt/nvim-linux-${arch}"
  $sudo ln -sf "/opt/nvim-linux-${arch}/bin/nvim" /usr/local/bin/nvim
  rm -rf "$tmpdir"
}

# Needed for nvim-treesitter parser installs.
install_tree_sitter() {
  if command -v tree-sitter >/dev/null 2>&1; then
    log "tree-sitter already installed."
    return
  fi

  local arch tmpdir sudo
  arch="$(target_arch x64 arm64)"

  log "Installing tree-sitter CLI..."
  tmpdir="$(mktemp -d)"
  curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-${arch}.gz" |
    gunzip >"$tmpdir/tree-sitter"
  sudo="$(sudo_cmd)"
  $sudo install -m 0755 "$tmpdir/tree-sitter" /usr/local/bin/tree-sitter
  rm -rf "$tmpdir"
}

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv already installed."
    return
  fi

  log "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$HOME/.local/bin" sh
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
    $sudo ln -sf "$DOTFILES_DIR/codex/.codex/notify-tmux.sh" /usr/local/bin/codex-notify-tmux
  fi

  log "Starting Codex app server..."
  codex app-server daemon bootstrap --remote-control
  codex app-server daemon start
}

install_claude() {
  export PATH="$HOME/.local/bin:$PATH"

  if command -v claude >/dev/null 2>&1; then
    log "Claude Code already installed."
  else
    log "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
  fi

  if [ -x "$HOME/.local/bin/claude" ]; then
    local sudo
    sudo="$(sudo_cmd)"
    $sudo ln -sf "$HOME/.local/bin/claude" /usr/local/bin/claude
  fi
}

setup_trustworthy_gradients() {
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

  if ! grep -qxF "Host github-trustworthy-gradients" "$HOME/.ssh/config"; then
    cat >>"$HOME/.ssh/config" <<'EOF'

Host github-trustworthy-gradients
  HostName github.com
  User git
  IdentityFile ~/.ssh/trustworthy-gradients
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
  fi

  if [ -d "$REPO_DIR/.git" ]; then
    log "Updating $REPO_DIR..."
    git -C "$REPO_DIR" fetch --all --prune
    git -C "$REPO_DIR" status --short --branch
  else
    log "Cloning trustworthy-gradients..."
    git clone "$REPO_SSH" "$REPO_DIR"
  fi

  log "Syncing trustworthy-gradients..."
  (
    cd "$REPO_DIR"
    UV_HTTP_TIMEOUT="$UV_HTTP_TIMEOUT" uv sync
  )

  log "Starting PG-19 preparation in background; logs: $REPO_DIR/prep.log"
  (
    cd "$REPO_DIR"
    nohup env UV_HTTP_TIMEOUT="$UV_HTTP_TIMEOUT" uv run python prepare.py >prep.log 2>&1 < /dev/null &
    log "PG-19 preparation pid: $!"
  )
}

install_dotfiles_repo() {
  mkdir -p "$HOME/Developer"

  if [ -s "$DOTFILES_ARCHIVE" ]; then
    log "Extracting uploaded dotfiles..."
    tar -xzf "$DOTFILES_ARCHIVE" -C "$HOME/Developer"
  elif [ -d "$DOTFILES_DIR/.git" ]; then
    log "Updating dotfiles..."
    git -C "$DOTFILES_DIR" fetch --all --prune
    git -C "$DOTFILES_DIR" status --short --branch
  else
    log "Cloning dotfiles..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi
}

# link_config keep|replace <src> <dest>: symlink dest -> src. An existing real
# file is left alone (keep) or moved to <dest>.before-gpu-setup (replace).
link_config() {
  local mode="$1" src="$2" dest="$3"

  [ -e "$src" ] || die "missing dotfiles path: $src"
  mkdir -p "$(dirname "$dest")"

  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    if [ "$mode" = keep ]; then
      log "$dest already exists; leaving it unchanged."
      return
    fi
    mv "$dest" "$dest.before-gpu-setup"
    log "Moved existing $dest to $dest.before-gpu-setup."
  fi

  ln -sfn "$src" "$dest"
}

link_dotfiles() {
  log "Linking portable dotfiles..."
  link_config keep "$DOTFILES_DIR/scripts/.scripts" "$HOME/.scripts"
  link_config replace "$DOTFILES_DIR/bash/.bashrc" "$HOME/.bashrc"
  link_config keep "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
  link_config keep "$DOTFILES_DIR/nvim/.config/nvim" "$HOME/.config/nvim"
  link_config replace "$DOTFILES_DIR/codex/.codex/config.gpu.toml" "$HOME/.codex/config.toml"
  link_config keep "$DOTFILES_DIR/codex/.codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
  link_config replace "$DOTFILES_DIR/claude/.claude/settings.gpu.json" "$HOME/.claude/settings.json"
  link_config keep "$DOTFILES_DIR/claude/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link_config keep "$DOTFILES_DIR/claude/.claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
  link_config keep "$DOTFILES_DIR/claude/.claude/tmux-notify.sh" "$HOME/.claude/tmux-notify.sh"
  link_config keep "$DOTFILES_DIR/git/.config/git/config" "$HOME/.config/git/config"
  link_config keep "$DOTFILES_DIR/lazygit/.config/lazygit/config.yml" "$HOME/.config/lazygit/config.yml"
}

verify_setup() {
  log "Verifying setup..."
  require_command tmux git lazygit delta nvim tree-sitter rg fd curl nnn fzf jq uv codex claude bwrap
  test -d "$DOTFILES_DIR/.git"
  test -x "$HOME/.scripts/gpu-setup.sh"
  test -L "$HOME/.bashrc"
  test -e "$HOME/.tmux.conf"
  test -e "$HOME/.config/nvim/init.lua"
  test -s "$HOME/.codex/config.toml"
  test -s "$HOME/.codex/AGENTS.md"
  test -s "$HOME/.claude/settings.json"
  test -s "$HOME/.claude/CLAUDE.md"
  test -s "$DEPLOY_KEY_DEST"
  test -d "$REPO_DIR/.git"
  codex --strict-config --version >/dev/null
  codex app-server daemon version
  claude --version >/dev/null
}

main() {
  if ! command -v apt-get >/dev/null 2>&1; then
    die "this script currently supports Ubuntu/Debian hosts with apt-get"
  fi

  touch "$HOME/.no_auto_tmux"
  install_packages
  install_lazygit
  install_delta
  install_fzf
  install_neovim
  install_tree_sitter
  install_uv
  install_dotfiles_repo
  link_dotfiles
  install_codex
  install_claude
  setup_trustworthy_gradients
  verify_setup
  nvidia-smi
  log "Done."
}

main "$@"
