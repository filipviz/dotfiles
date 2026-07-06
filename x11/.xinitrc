[ -f "$HOME/.xprofile" ] && . "$HOME/.xprofile"

"$HOME/.local/bin/dwm-status" &

exec dwm
