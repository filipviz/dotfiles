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
# (Ghostty does) and tmux >= 3.5; older tmux fails the grep and we just notify.
pane_visible() {
  in_tmux || return 1
  [ "$(pane_fmt '#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}}')" = 1 ] || return 1
  tmux list-clients -t "$(pane_fmt '#{session_id}')" -F '#{client_flags}' 2>/dev/null | grep -q focused
}

notify_system() {
  if [ "$(uname)" = Darwin ]; then
    /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
  elif in_tmux; then
    # OSC 777 desktop notification, wrapped in a tmux passthrough sequence so
    # it reaches the outer terminal. Ghostty shows these natively, even when
    # the pane lives on a remote host across SSH.
    pane_tty="$(pane_fmt '#{pane_tty}')"
    if [ -n "$pane_tty" ] && [ -w "$pane_tty" ]; then
      printf '\033Ptmux;\033\033]777;notify;%s;%s\033\033\\\033\\' "$1" "$2" > "$pane_tty"
    fi
  else
    printf '\033]777;notify;%s;%s\033\\' "$1" "$2" > /dev/tty 2>/dev/null || true
  fi
}

case "$label" in
  claude) app="Claude" ;;
  codex) app="Codex" ;;
  *) app="$label" ;;
esac

loc=""
in_tmux && loc="$(pane_fmt '#{session_name}:#{window_index}.#{pane_index}')"
title="$app${loc:+ $loc}"

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
