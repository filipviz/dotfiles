# Used on remote hosts

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

set -o vi
PS1='[\u@\h \W]\$ '
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export PATH="$HOME/.local/bin:$PATH"

# Disable ctrl-s terminal freeze (nvim uses <C-s> for LSP signature help).
stty stop undef

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
  if [[ -n $TMUX ]]; then
    tmux load-buffer -w -
  else
    printf '\033]52;c;'
    base64 -w 0
    printf '\a'
  fi
}

if command -v fzf >/dev/null 2>&1; then
  fzf_init=$(fzf --bash) || return 1
  eval "$fzf_init" || return 1
  unset fzf_init

  ff() {
    fzf --height 40% --layout reverse \
      --preview 'head -n $FZF_PREVIEW_LINES {} | cat -n' \
      --bind 'enter:become(nvim {})'
  }
fi
