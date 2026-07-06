[ -f "$HOME/.xprofile" ] && . "$HOME/.xprofile"

dunst &
"$HOME/.local/bin/dwm-status" &

exec dwm
