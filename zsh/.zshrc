setopt autocd
stty stop undef  # Disable ctrl-s to freeze terminal.
setopt interactive_comments

export CODEX_CODE_MODE_HOST_PATH=$HOME/.local/bin/codex-code-mode-host

# history
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt share_history
setopt hist_ignore_dups
# Ignore commands starting with a space
setopt hist_ignore_space

# prompt: time, cwd, git branch
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats '%b '
setopt PROMPT_SUBST
PROMPT='%F{green}%*%f %F{blue}%~%f %F{red}${vcs_info_msg_0_}%f$ '

# Miscellaneous setup.
alias ls='ls --color=auto'
alias dl-audio="yt-dlp -f 140 --embed-chapters"
alias ank="codex -C /home/f/dev/utils"
alias rs='redshift -P -O'
alias cb='xclip -selection clipboard'
alias pb='xclip -selection clipboard -out'
alias lg="lazygit"

# Dictionary lookup via sdcv (StarDict dicts in ~/.local/share/stardict/dic).
# Several dicts store entries as raw HTML (some with multi-line style/script
# blocks); strip it for terminal reading. Plain-text dicts pass through.
dict() {
  setopt local_options pipe_fail
  sdcv -n -c "$@" \
    | perl -CS -0777 -pe '
        use utf8; use Text::Wrap;
        s#<style[^>]*>.*?</style>##gs;
        s#<script[^>]*>.*?</script>##gs;
        s#<br ?/?>#\n#g;
        s#</(?:p|li|ol|ul|div|h[1-6]|dt|dd)>#\n#g;
        s#<li>#  • #g;
        s#<[^>]*>##g;
        s#&lt;#<#g; s#&gt;#>#g; s#&quot;#"#g; s#&nbsp;# #g;
        s#&\#(\d+);#chr($1)#ge; s#&\#x([0-9a-fA-F]+);#chr(hex($1))#ge;
        s#&amp;#&#g;
        s#^\s*show full / hide\s*$##gm;  # collapse-toggle links in Smith dicts
        $Text::Wrap::columns = 80;
        s#^(.{80,})$#wrap("", "", $1)#gme;
        s#\n{3,}#\n\n#g;
      ' \
    | less -FRX
}

export GPG_TTY=$TTY

# Completion.
autoload -Uz compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
# Reuse the completion dump if it's less than a day old; else rebuild it.
# (compinit leaves an unchanged dump's mtime alone, hence the touch.)
zcompdump_path="${ZDOTDIR:-$HOME}/.zcompdump-$ZSH_VERSION"
if [[ -f $zcompdump_path && -n $(find "$zcompdump_path" -mmin -1440) ]]; then
  compinit -C -d "$zcompdump_path" || return 1
else
  compinit -d "$zcompdump_path" || return 1
  touch "$zcompdump_path" || return 1
fi
unset zcompdump_path
_comp_options+=(globdots)  # Include hidden files.

# vi mode
bindkey -v
KEYTIMEOUT=1

# Use vim keys in tab complete menu:
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -v '^?' backward-delete-char

# Change cursor shape for different vi modes.
zle-keymap-select() {
  case $KEYMAP in
    vicmd) printf '\e[1 q' ;;      # block
    viins|main) printf '\e[5 q' ;; # beam
  esac
}
zle -N zle-keymap-select
zle-line-init() {
  zle -K viins
  printf '\e[5 q'
}
zle -N zle-line-init

# Reset to block cursor before running commands, so TUIs that don't set
# a cursor style (claude, nnn, lazygit, ...) start with the block.
preexec() { printf '\e[1 q' }

# fzf bindings and helper
fzf_init=$(fzf --zsh) || return 1
eval "$fzf_init" || return 1
unset fzf_init
ff() {
  fzf --height 40% --layout reverse \
    --preview 'head -n $FZF_PREVIEW_LINES {} | cat -n' \
    --bind 'enter:become(nvim {})'
}

n() {
  if (( NNNLVL != 0 )); then
    print -u2 "nnn is already running"
    return 1
  fi

  local -x NNN_TMPFILE="${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.lastd"
  command nnn "$@" || return

  if [[ -f $NNN_TMPFILE ]]; then
    source "$NNN_TMPFILE" || return
    rm -- "$NNN_TMPFILE"
  fi
}
# Launch nnn with ctrl-o:
bindkey -s '^o' '^un\n'

# Edit line in vim with ctrl-e:
autoload edit-command-line
zle -N edit-command-line
bindkey '^e' edit-command-line

# Load zsh-syntax-highlighting (must be last)
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
