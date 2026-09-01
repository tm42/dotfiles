#!/bin/zsh
# Status-bar housekeeping, run from status-right. tmux re-expands that on every
# redraw, so this runs both on the status-interval tick and within about 20ms of
# any pane, window or session switch — which is what makes a notice clear as you
# arrive without a hook to push it.
#
# THE NOTICE replaces `display-message`, whose timeout tmux cancels on the next
# key you press: a Stop in window 4 vanished because you kept typing in window 1.
# This one lives in the bar, so only its own pane coming into view clears it —
# or HOLD seconds passing.
#
# It refreshes the client only when it cleared something, so the redraw that
# causes finds nothing to do and stops there.
emulate -L zsh
zmodload zsh/datetime

HOLD=30   # seconds a notice survives if you never visit its pane

notice=$(tmux show -gqv @notice)
if [[ -n $notice ]]; then
  at=$(tmux show -gqv @notice_at)
  src=$(tmux show -gqv @notice_pane)
  # The notifier's own foreground test: current pane, current window, and a
  # client attached to that session.
  seen=$(tmux display -p -t "$src" \
        '#{&&:#{session_attached},#{&&:#{pane_active},#{window_active}}}' 2>/dev/null)
  if (( EPOCHSECONDS - ${at:-0} >= HOLD )) || [[ $seen == 1 ]]; then
    tmux set -gu @notice \; set -gu @notice_at \; set -gu @notice_pane \; refresh-client -S
    notice=''
  fi
fi

[[ -n $notice ]] && print -rn -- "#[bg=#e0af68,fg=#1a1b26,bold]$notice#[bg=#24283b,fg=#565f89] "
exit 0
