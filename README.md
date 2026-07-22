# dotfiles

Used on a ThinkPad x220 running Arch Linux, and may need adjustment if used elsewhere.

To install the stow packages:
```sh
cd ~/dev/dotfiles
stow -t "$HOME" alacritty bash claude codex git lazygit newsboat nvim scripts tmux x11 zsh
```

To install the root-owned Codex guardrails:
```sh
sudo install -Dm0644 -o root -g root \
  system/etc/codex/requirements.toml \
  /etc/codex/requirements.toml
```

