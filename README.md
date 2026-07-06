# dotfiles

GNU Stow packages, hard-coded for this machine (ThinkPad X220, Arch,
dwm/X11, alacritty). The repo lives outside `$HOME`, so always pass the
target:

```sh
cd ~/dev/dotfiles
stow -t "$HOME" alacritty bash claude codex dwm git lazygit newsboat nvim scripts tmux x11 zsh
```

Notes:

- `x11/` holds `.xprofile`, `.xinitrc`, and `.local/bin/dwm-status` (the
  status-bar loop started from `.xinitrc`).
- `dwm/` links `config.h` into the dwm source clone at `~/dev/dwm`
  (package path `dwm/dev/dwm/config.h`, so the standard `$HOME`-target
  stow command lands it there). Rebuild with `make && sudo make install`
  in `~/dev/dwm` after changing it.
- `claude/` and `codex/` link individual files into the live `~/.claude`
  and `~/.codex` state directories (which must already exist). GPU-host
  config variants (`claude/.claude/settings.gpu.json`,
  `codex/.codex/config.gpu.toml`) are excluded from local stowing and
  linked into place on freshly rented GPU instances by
  `scripts/.scripts/gpu-setup.sh`, which `gpu-provision.sh` uploads and
  runs.
- `bash/` is for remote hosts; the local shell is zsh.
- macOS support (ghostty, brew in `.zprofile`, the OCR-screenshot
  script, per-OS fallbacks) was removed in the commit labeled
  "Remove macOS support" — recover it from that commit's parent.
