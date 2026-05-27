if [ -n "${DOTFILES_BASHRC_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
export DOTFILES_BASHRC_LOADED=1

export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export PATH="$HOME/.scripts:$HOME/.local/bin:$PATH"

if command -v fzf >/dev/null 2>&1; then
  if fzf --bash >/dev/null 2>&1; then
    eval "$(fzf --bash)"
  else
    [ -r /usr/share/doc/fzf/examples/key-bindings.bash ] && . /usr/share/doc/fzf/examples/key-bindings.bash
    [ -r /usr/share/doc/fzf/examples/completion.bash ] && . /usr/share/doc/fzf/examples/completion.bash
  fi
fi
