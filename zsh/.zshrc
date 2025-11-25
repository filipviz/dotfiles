autoload -U colors && colors
setopt autocd
stty stop undef  # Disable ctrl-s to freeze terminal.
setopt interactive_comments

# autoload -Uz vcs_info
# precmd() { vcs_info }
# zstyle ':vcs_info:git:*' formats '%b '
# setopt PROMPT_SUBST
# PROMPT='%F{green}%*%f %F{blue}%~%f %F{red}${vcs_info_msg_0_}%f$ '

# Miscellaneous setup.
alias ls='ls --color=auto'
alias sqlite="/opt/homebrew/opt/sqlite/bin/sqlite3"
alias ding="afplay /System/Library/Sounds/Glass.aiff"

export GPG_TTY=$(tty)

# Basic auto/tab complete:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
if [[ ! -f $ZDOTDIR/.zcompdump ]]; then compinit -i
else
  compinit -C
fi
# compinit
_comp_options+=(globdots)		# Include hidden files.

# vi mode
bindkey -v
export KEYTIMEOUT=1

# Use vim keys in tab complete menu:
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -v '^?' backward-delete-char

# Change cursor shape for different vi modes.
function zle-keymap-select () {
    case $KEYMAP in
        vicmd) echo -ne '\e[1 q';;      # block
        viins|main) echo -ne '\e[5 q';; # beam
    esac
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q' # Use beam shape cursor on startup.
preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.

# fzf bindings and helper
source <(fzf --zsh)
ff() {
  fzf --height 40% --layout reverse \
      --preview 'head -n $FZF_PREVIEW_LINES {} | cat -n' \
      --bind 'enter:become(nvim {})'
}

alacritty_theme() {
  [[ -z "$ALACRITTY_WINDOW_ID" ]] && return
  local base="$HOME/.config/alacritty"
  if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -qi "Dark"; then
    theme_file="$base/everforest_dark.toml"
  else
    theme_file="$base/everforest_light.toml"
  fi
  alacritty msg config "$(cat "$theme_file")"
}
alacritty_theme

n ()
{
    # Block nesting of nnn in subshells
    [ "${NNNLVL:-0}" -eq 0 ] || {
        echo "nnn is already running"
        return
    }

    # The behaviour is set to cd on quit (nnn checks if NNN_TMPFILE is set)
    # If NNN_TMPFILE is set to a custom path, it must be exported for nnn to
    # see. To cd on quit only on ^G, remove the "export" and make sure not to
    # use a custom path, i.e. set NNN_TMPFILE *exactly* as follows:
    #      NNN_TMPFILE="${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.lastd"
    export NNN_TMPFILE="${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.lastd"

    # The command builtin allows one to alias nnn to n, if desired, without
    # making an infinitely recursive alias
    command nnn "$@"

    [ ! -f "$NNN_TMPFILE" ] || {
        . "$NNN_TMPFILE"
        rm -f -- "$NNN_TMPFILE" > /dev/null
    }
}
# Launch nnn with ctrl-o:
bindkey -s '^o' 'n\n'

# Edit line in vim with ctrl-e:
autoload edit-command-line; zle -N edit-command-line
bindkey '^e' edit-command-line

# Load zsh-syntax-highlighting
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
export PATH="/opt/homebrew/opt/sqlite/bin:$PATH"
export PATH="/Users/filip/.antigravity/antigravity/bin:$PATH"
