# Used on remote hosts

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

set -o vi
PS1='[\u@\h \W]\$ '
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export PATH="$HOME/.scripts:$HOME/.local/bin:$PATH"

# Disable ctrl-s terminal freeze (nvim uses <C-s> for LSP signature help).
# 2>/dev/null: this file is also sourced by non-interactive ssh shells.
stty stop undef 2>/dev/null

HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoredups:ignorespace
shopt -s histappend

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias lg="lazygit"

alias cb='xclip -selection clipboard'
alias pb='xclip -selection clipboard -out'
clip() {
  if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    tmux load-buffer -w -
  else
    printf '\033]52;c;'
    base64 | tr -d '\n'
    printf '\a'
  fi
}

if command -v fzf >/dev/null 2>&1; then
  if fzf --bash >/dev/null 2>&1; then
    eval "$(fzf --bash)"
  else
    [ -r /usr/share/doc/fzf/examples/key-bindings.bash ] && . /usr/share/doc/fzf/examples/key-bindings.bash
    [ -r /usr/share/doc/fzf/examples/completion.bash ] && . /usr/share/doc/fzf/examples/completion.bash
  fi

  ff() {
    fzf --height 40% --layout reverse \
      --preview 'head -n $FZF_PREVIEW_LINES {} | cat -n' \
      --bind 'enter:become(nvim {})'
  }
fi
