# dotfiles

GNU Stow packages, hard-coded for this machine (ThinkPad X220, Arch,
dwm/X11, alacritty). The repo lives outside `$HOME`, so always pass the
target:

```sh
cd ~/dev/dotfiles
stow -t "$HOME" alacritty bash claude codex git lazygit newsboat nvim scripts tmux x11 zsh
```

Install the tracked Codex guardrails as a root-owned system policy (not a
symlink into this writable repository):

```sh
sudo install -Dm0644 -o root -g root \
  system/etc/codex/requirements.toml \
  /etc/codex/requirements.toml
```

Notes:

- `x11/` is the complete X11 session package: `.xprofile`, `.xinitrc`,
  dunst and dwm configuration, and X11-oriented commands including
  `amphetamine` and `dwm-status`. `.xinitrc` starts dunst and dwm-status,
  then execs dwm.
- `newsboat/` follows XDG: config, urls, and feed scripts live in
  `~/.config/newsboat` (this repo); runtime state (cache.db, history,
  bookmarks) lives in `~/.local/share/newsboat`, outside the repo.
- `x11/dev/dwm/config.h` links into the dwm source clone at `~/dev/dwm`.
  Rebuild with `make && sudo make install` in `~/dev/dwm` after changing
  it. The clone also carries a small local patch publishing each client's
  tag as `_NET_WM_DESKTOP`, which `claude/.claude/tmux-notify.sh` reads to
  put the dwm tag in notifications.
- `claude/` and `codex/` link individual files into the live `~/.claude`
  and `~/.codex` state directories (which must already exist). GPU-host
  config variants (`claude/.claude/settings.gpu.json`,
  `codex/.codex/config.gpu.toml`) are excluded from local stowing and
  linked into place on freshly rented GPU instances by
  `scripts/.local/bin/gpu-setup.sh`, which `gpu-provision.sh` uploads
  and runs.
- `zsh/` includes the sdcv result ordering used by the `dict` function in
  `.zshrc`; the StarDict dictionaries themselves live in
  `~/.local/share/stardict/dic`, outside the repo.
- `bash/` is for remote hosts; the local shell is zsh.
- macOS support (ghostty, brew in `.zprofile`, the OCR-screenshot
  script, per-OS fallbacks) was removed in the commit labeled
  "Remove macOS support" — recover it from that commit's parent.
