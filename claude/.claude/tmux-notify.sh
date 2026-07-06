#!/bin/sh
# Agent hook: tmux pane indicators + dunst notifications.
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

# X window displaying this session: in tmux, WINDOWID from the attached
# client's environment (the hook's own WINDOWID may be another window's,
# inherited from wherever the tmux server started); otherwise our own.
x_window() {
  if in_tmux; then
    pid="$(tmux list-clients -t "$(pane_fmt '#{session_id}')" -F '#{client_pid}' 2>/dev/null | head -n 1)"
    [ -n "$pid" ] && tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WINDOWID=//p'
  else
    printf '%s' "${WINDOWID:-}"
  fi
}

# dwm tag (1-based) of an X window, via the _NET_WM_DESKTOP property our
# patched dwm publishes. Prints nothing if unknown.
dwm_tag() {
  [ -n "$1" ] || return 0
  xprop -id "$1" -notype _NET_WM_DESKTOP 2>/dev/null |
    awk '$3 ~ /^[0-9]+$/ { print $3 + 1 }'
}

# True when the user is looking at this pane, i.e. a notification would be
# noise. In tmux: pane on-screen in an attached client whose terminal window
# has focus (needs focus events and tmux >= 3.5; older tmux fails the grep
# and we just notify). Outside tmux: our window is dwm's active window.
user_watching() {
  if in_tmux; then
    [ "$(pane_fmt '#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}}')" = 1 ] || return 1
    tmux list-clients -t "$(pane_fmt '#{session_id}')" -F '#{client_flags}' 2>/dev/null | grep -q focused
  else
    [ -n "$wid" ] &&
      [ "$(xprop -root -notype _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}')" = "$(printf '0x%x' "$wid")" ]
  fi
}

notify_system() {
  command -v notify-send >/dev/null 2>&1 && notify-send "$1" "$2" >/dev/null 2>&1 || true
}

# First words of the agent's message, for the notification body. Codex sends
# it in the payload (last-assistant-message), claude's Notification payload
# has .message, and claude's Stop payload only carries the transcript path.
last_message() {
  msg="$(printf '%s' "$payload" | jq -r '."last-assistant-message" // .message // empty' 2>/dev/null)"
  if [ -z "$msg" ]; then
    tp="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
    [ -n "$tp" ] && [ -r "$tp" ] && msg="$(tail -n 100 "$tp" | jq -rs \
      '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // empty' 2>/dev/null)"
  fi
  printf '%s' "$msg" | tr '\n\t' '  ' |
    awk '{ gsub(/  +/, " ") } length > 80 { print substr($0, 1, 79) "…"; next } { print }'
}

case "$label" in
  claude) app="Claude" ;;
  codex) app="Codex" ;;
  *) app="$label" ;;
esac

wid="$(x_window)"
tag="$(dwm_tag "$wid")"
loc="${tag:+tag $tag}"
if in_tmux; then
  win="$(pane_fmt '#{window_index}')"
  [ -n "$win" ] && loc="$loc${loc:+, }tmux $win"
fi
title="$app${loc:+ ($loc)}"

case "$event" in
  prompt)
    set_title "✳ $label"
    ;;
  notification)
    msg="$(last_message)"
    [ -n "$msg" ] || msg="Needs attention"
    set_title "✋ $label"
    ring_bell
    user_watching || notify_system "$title" "$msg"
    ;;
  stop)
    msg="$(last_message)"
    [ -n "$msg" ] || msg="Finished"
    set_title "✔ $label"
    ring_bell
    user_watching || notify_system "$title" "$msg"
    ;;
  clear)
    set_title ""
    ;;
esac

exit 0
