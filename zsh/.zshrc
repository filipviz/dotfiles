autoload -U colors && colors
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
  sdcv -n -c "$@" 2>/dev/null \
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

export GPG_TTY=$(tty)

# Basic auto/tab complete:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
# Reuse the completion dump if it's less than a day old; else rebuild it.
# (compinit leaves an unchanged dump's mtime alone, hence the touch.)
if [[ -n $(find ${ZDOTDIR:-$HOME}/.zcompdump -mmin -1440 2>/dev/null) ]]; then
  compinit -C
else
  compinit -i && touch ${ZDOTDIR:-$HOME}/.zcompdump
fi
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

# Reset to block cursor before running commands, so TUIs that don't set
# a cursor style (claude, nnn, lazygit, ...) start with the block.
preexec() { echo -ne '\e[1 q' }

# fzf bindings and helper
if command -v fzf &> /dev/null; then
	source <(fzf --zsh)
	ff() {
	  fzf --height 40% --layout reverse \
		  --preview 'head -n $FZF_PREVIEW_LINES {} | cat -n' \
		  --bind 'enter:become(nvim {})'
		}
fi

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
bindkey -s '^o' '^un\n'

# Edit line in vim with ctrl-e:
autoload edit-command-line; zle -N edit-command-line
bindkey '^e' edit-command-line

# Load zsh-syntax-highlighting (must be last)
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
fpath=(~/.grok/completions/zsh $fpath)
autoload -Uz compinit && compinit -C
# <<< grok installer <<<
