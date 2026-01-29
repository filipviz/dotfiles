#!/usr/bin/env bash
set -euo pipefail

PKGS=(build-essential python3-dev tmux git neovim ripgrep fd-find npm curl)
BASHRC="$HOME/.bashrc"
TMUXCONF="$HOME/.tmux.conf"
NVIM_INIT="$HOME/.config/nvim/init.lua"

log() {
  printf '%s\n' "$*"
}

append_if_missing() {
  local line="$1"
  local file="$2"

  if [ ! -f "$file" ]; then
    touch "$file"
  fi

  if ! grep -qxF "$line" "$file"; then
    printf '%s\n' "$line" >> "$file"
  fi
}

require_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "This script currently supports Debian/Ubuntu (apt-get)."
    exit 1
  fi
}

get_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    echo ""
  elif command -v sudo >/dev/null 2>&1; then
    echo "sudo"
  else
    log "Need root privileges or sudo to install packages."
    exit 1
  fi
}

install_packages() {
  local sudo_cmd="$1"

  log "Updating apt and installing packages..."
  $sudo_cmd apt-get update
  $sudo_cmd apt-get install -y "${PKGS[@]}"
}

setup_bashrc() {
  append_if_missing "set -o vi" "$BASHRC"
  append_if_missing "export VISUAL=nvim" "$BASHRC"
  append_if_missing "export EDITOR=nvim" "$BASHRC"
}

setup_tmux() {
  append_if_missing "set -g mouse on" "$TMUXCONF"
  append_if_missing "set -g set-clipboard on" "$TMUXCONF"
  append_if_missing "set -g status-keys vi" "$TMUXCONF"
  append_if_missing "set -g mode-keys vi" "$TMUXCONF"
  append_if_missing "set -g focus-events on" "$TMUXCONF"
  append_if_missing "bind -r k select-pane -U" "$TMUXCONF"
  append_if_missing "bind -r j select-pane -D" "$TMUXCONF"
  append_if_missing "bind -r h select-pane -L" "$TMUXCONF"
  append_if_missing "bind -r l select-pane -R" "$TMUXCONF"
  append_if_missing "bind -r H resize-pane -L 5" "$TMUXCONF"
  append_if_missing "bind -r J resize-pane -D 5" "$TMUXCONF"
  append_if_missing "bind -r K resize-pane -U 5" "$TMUXCONF"
  append_if_missing "bind -r L resize-pane -R 5" "$TMUXCONF"
  append_if_missing "bind '\"' split-window -c \"#{pane_current_path}\"" "$TMUXCONF"
  append_if_missing "bind % split-window -h -c \"#{pane_current_path}\"" "$TMUXCONF"
  append_if_missing "bind c new-window -c \"#{pane_current_path}\"" "$TMUXCONF"
  append_if_missing "set -s escape-time 0" "$TMUXCONF"
  append_if_missing "set -g history-limit 50000" "$TMUXCONF"
}

setup_nvim() {
  if [ -f "$NVIM_INIT" ]; then
    log "Neovim config already exists at $NVIM_INIT; skipping."
    return
  fi

  log "Writing minimal Neovim config to $NVIM_INIT"
  mkdir -p "$(dirname "$NVIM_INIT")"

  cat <<'EOF' > "$NVIM_INIT"
vim.g.mapleader = " "

vim.opt.mouse = ""
vim.opt.splitright = true
vim.opt.undofile = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.clipboard = "unnamedplus"
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.list = true
vim.opt.listchars = { trail = "-", nbsp = "+", tab = "  ", extends = ">", precedes = "<" }
vim.opt.shortmess:append("I")
vim.opt.updatetime = 500

vim.opt.grepprg = "rg --vimgrep"
vim.opt.grepformat = "%f:%l:%c:%m"
vim.cmd.packadd("cfilter")

-- netrw
vim.g.netrw_keepdir = 0
vim.g.netrw_winsize = 18
vim.g.netrw_banner = 0

-- Keymaps
vim.keymap.set("n", "<leader>e", "<Cmd>Lexplore<CR>")
vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", { silent = true })

for _, key in ipairs({ "h", "j", "k", "l" }) do
  vim.keymap.set("n", "<C-" .. key .. ">", "<C-w>" .. key)
  vim.keymap.set("t", "<C-" .. key .. ">", "<C-\\><C-n><C-w>" .. key)
end
EOF
}

setup_fd() {
  if command -v fd >/dev/null 2>&1; then
    return
  fi

  if command -v fdfind >/dev/null 2>&1; then
    append_if_missing "alias fd=fdfind" "$BASHRC"
  fi
}

install_codex() {
  local sudo_cmd="$1"

  log "Installing @openai/codex..."
  $sudo_cmd npm install -g @openai/codex
}

install_uv() {
  local sudo_cmd="$1"

  log "Installing uv..."

  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://astral.sh/uv/install.sh | sh
  else
    log "curl or wget not found; installing curl..."
    $sudo_cmd apt-get install -y curl
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
}

main() {
  require_apt
  local sudo_cmd
  sudo_cmd=$(get_sudo)

  install_packages "$sudo_cmd"
  setup_bashrc
  setup_tmux
  setup_nvim
  setup_fd

  install_uv "$sudo_cmd" &
  local uv_pid=$!
  install_codex "$sudo_cmd"
  wait "$uv_pid"

  log "Done. Restart your shell to pick up .bashrc changes."
}

main "$@"
