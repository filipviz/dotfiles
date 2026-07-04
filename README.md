# dotfiles

GNU Stow packages. The repo lives outside `$HOME`, so always pass the target:

```sh
cd ~/Developer/dotfiles
stow -t "$HOME" bash claude codex ghostty git lazygit newsboat nvim scripts tmux zsh
```

`claude/` and `codex/` link individual files into the live `~/.claude` and
`~/.codex` state directories (which must already exist). GPU-host config
variants (`claude/.claude/settings.gpu.json`, `codex/.codex/config.gpu.toml`)
are excluded from local stowing and linked into place on freshly rented GPU
instances by `scripts/.scripts/gpu-setup.sh`, which `gpu-provision.sh` uploads
and runs.
