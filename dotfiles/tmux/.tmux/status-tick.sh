#!/bin/zsh
# Status-bar housekeeping, run from status-right. tmux re-expands that on every
# redraw, so this runs on the status-interval tick and again within about 20ms
# of any pane, window or session switch. That switch-driven run still sees the
# frame before the switch, so a notice whose pane you have just reached goes on
# the tick after it: 2.0s measured at status-interval 5, and bounded by it. No
# hook pushes it — one measured against this cost seven lines and a second
# concurrent sweep per switch, to save at most those two seconds.
#
# THE NOTICE replaces `display-message`, whose timeout tmux cancels on the next
# key you press: a Stop in window 4 vanished because you kept typing in window 1.
# This one lives in the bar, so only its own pane coming into view clears it —
# or HOLD seconds passing.
#
# THE SWEEP retires a "Working" its pane has outlived. State is latched by hooks,
# and Claude fires none when you interrupt a turn with Esc or when it is killed,
# so the latch outlives the turn with nothing to clear it. What separates the two
# is that a working pane redraws: measured on 2.1.252 against a real turn, no two
# consecutive 3s samples of the screen were identical while it streamed, and the
# screen then held one value for the 50s after Esc. FREEZE is ten times that 3s
# sampling floor, so the cost of being wrong is a tab that reads Working for half
# a minute too long rather than one that goes quiet mid-turn.
#
# Nothing filters on the pane's command, and testing it would be a bug: a killed
# agent leaves the pane back at zsh, which is exactly the case with no hook to
# clear it. No filter is needed either — Codex declares only PermissionRequest
# and Stop, so `working` is Claude's alone.
#
# Both refresh the client only when they changed something, so the redraw that
# causes finds nothing to do and stops there.
emulate -L zsh
zmodload zsh/datetime

HOLD=30     # seconds a notice survives if you never visit its pane
FREEZE=30   # seconds of an unchanging screen before "Working" is retired

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

tmux list-panes -a -F '#{pane_id} #{@agent_state} #{@agent_screen} #{@agent_screen_at}' 2>/dev/null |
while read -r id state hash hash_at; do
  [[ $state == working ]] || continue
  now=$(tmux capture-pane -p -t "$id" 2>/dev/null | cksum | cut -d' ' -f1)
  if [[ $now != $hash ]]; then
    tmux set -p -t "$id" @agent_screen "$now" \; set -p -t "$id" @agent_screen_at "$EPOCHSECONDS"
  elif (( EPOCHSECONDS - ${hash_at:-EPOCHSECONDS} >= FREEZE )); then
    tmux set -pu -t "$id" @agent_state \; set -pu -t "$id" @agent_screen \; \
         set -pu -t "$id" @agent_screen_at \; refresh-client -S
  fi
done

[[ -n $notice ]] && print -rn -- "#[bg=#e0af68,fg=#1a1b26,bold]$notice#[bg=#24283b,fg=#565f89] "
exit 0
