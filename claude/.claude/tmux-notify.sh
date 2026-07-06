#!/bin/sh
# Agent hook: tmux pane indicators + system notifications.
# Usage: tmux-notify.sh prompt|notification|stop|clear [label]   (JSON on stdin)
#
#   prompt        mark the pane busy (UserPromptSubmit)
#   notification  mark the pane as needing input; bell + system notification
#   stop          mark the pane done; bell + system notification
#   clear         reset the pane title (SessionEnd)
#
# label defaults to "claude"; codex calls pass "codex" (see codex/.codex/notify-tmux.sh).

event="${1:-}"
label="${2:-claude}"
payload="$(cat 2>/dev/null || true)"

in_tmux() {
  [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1
}

pane_fmt() {
  tmux display-message -p -t "$TMUX_PANE" -F "$1" 2>/dev/null
}

set_title() {
  if in_tmux; then
    tmux select-pane -t "$TMUX_PANE" -T "$1" 2>/dev/null || true
  fi
}

# Ring the bell in the pane so tmux flags its window in the status line.
ring_bell() {
  in_tmux || return 0
  pane_tty="$(pane_fmt '#{pane_tty}')"
  if [ -n "$pane_tty" ] && [ -w "$pane_tty" ]; then
    printf '\a' > "$pane_tty"
  fi
}

# True when the pane is on-screen in an attached client whose terminal window
# has focus, i.e. the user is actually looking at it and a system notification
# would be noise. Focus tracking needs the terminal to send focus events
# and tmux >= 3.5; older tmux fails the grep and we just notify.
pane_visible() {
  in_tmux || return 1
  [ "$(pane_fmt '#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}}')" = 1 ] || return 1
  tmux list-clients -t "$(pane_fmt '#{session_id}')" -F '#{client_flags}' 2>/dev/null | grep -q focused
}

notify_system() {
  command -v notify-send >/dev/null 2>&1 && notify-send "$1" "$2" >/dev/null 2>&1 || true
}

# dwm tag (1-based) of the terminal window showing this session: tmux client
# pid -> WINDOWID from its environment -> _NET_WM_DESKTOP, which our patched
# dwm publishes. Prints nothing if any link in the chain is missing.
dwm_tag() {
  pid="$(tmux list-clients -t "$(pane_fmt '#{session_id}')" -F '#{client_pid}' 2>/dev/null | head -n 1)"
  [ -n "$pid" ] || return 0
  wid="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WINDOWID=//p')"
  [ -n "$wid" ] || return 0
  xprop -id "$wid" -notype _NET_WM_DESKTOP 2>/dev/null |
    awk '$3 ~ /^[0-9]+$/ { print $3 + 1 }'
}

case "$label" in
  claude) app="Claude" ;;
  codex) app="Codex" ;;
  *) app="$label" ;;
esac

loc="" tag=""
if in_tmux; then
  loc="$(pane_fmt '#{session_name}:#{window_index}.#{pane_index}')"
  tag="$(dwm_tag)"
fi
title="$app${loc:+ $loc}${tag:+ · tag $tag}"

case "$event" in
  prompt)
    set_title "✳ $label"
    ;;
  notification)
    msg="$(printf '%s' "$payload" | jq -r '.message // .notification_type // empty' 2>/dev/null | tr '\\"' "'")"
    [ -n "$msg" ] || msg="Needs attention"
    set_title "✋ $label"
    ring_bell
    pane_visible || notify_system "$title" "$msg"
    ;;
  stop)
    set_title "✔ $label"
    ring_bell
    pane_visible || notify_system "$title" "Finished"
    ;;
  clear)
    set_title ""
    ;;
esac

exit 0
