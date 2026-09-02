#!/bin/zsh
# Coding-agent hook → tmux pane state + status strip + optional macOS notification.
#
# One script, two agents. The agent name is argument 1 and is used only for the
# label, because Claude Code and Codex deliver the same hook payload: a JSON
# object on stdin carrying .hook_event_name and .cwd, from a command named in
#   ~/.claude/settings.json   UserPromptSubmit, PermissionRequest, Notification, Stop
#   ~/.codex/hooks.json       PermissionRequest, Stop
# The one difference is that Codex's PermissionRequest has no .message — it
# carries .tool_name and .tool_input.description instead.
#
# ── What @agent_state is for ────────────────────────────────────────────────
# .tmux.conf renders a pane's state as "<State> | <name>", in Codex's own words,
# for both agents. Codex publishes those words in its pane title and needs no
# help; Claude publishes a constant "✳ <session>" that never changes, not even
# while it is working, so every state Claude has comes from here.
#
#   working   a turn started. Claude only — Codex's title says Working itself.
#   wait      blocked on you, from PermissionRequest. Codex says "Action
#             Required" in its title too, so this is Claude's only source and
#             Codex's backstop.
#   ready     a turn ended, or the agent has been waiting on you long enough to
#             say so. BOTH agents need this: Codex's title reports Ready for a
#             finished turn and for a pane untouched since yesterday alike, so
#             the title cannot tell you a question is waiting.
#   unset     nothing pending. .tmux.conf clears `ready` when you visit the
#             pane; `wait` survives, because an approval you have looked at and
#             not answered is still an approval.
#
# Notification is deliberately NOT wait. Claude fires it both for a permission
# prompt and after sitting idle ≥60s, and the second is the opposite of blocked
# on you — it is precisely ready. Mapping both to wait pinned every Claude pane
# you walked away from to "Action Required" forever, since visiting never clears
# wait. PermissionRequest is the event that means only the one thing, so wait
# comes from there; Notification then declines to downgrade an existing wait,
# because Claude fires it 60s into a prompt that is still pending.
#
# ── The notification ────────────────────────────────────────────────────────
# The tmux status strip fires only when the agent's pane is in the background —
# if you're looking at it you already know. Always exits 0: a hook that errors
# would nag the agent, not you.
#
#   AGENT_NOTIFY_BANNER  non-empty to also raise a macOS notification. Unset = no
#                        banner, which also means no notification at all outside
#                        tmux. INSTALL.md step 7 suggests where to export it.
#   AGENT_NOTIFY_SOUND   alert sound for that banner, or "" for silent (default
#                        Submarine). No effect while the banner is off.

emulate -L zsh
zmodload zsh/datetime
setopt no_unset extended_glob     # extended_glob: the ##pattern strip below needs it
exec 2>/dev/null

agent=${1:-claude}
soft=''      # set by Notification only: never overwrite a pending wait
payload=$(cat)
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // "Stop"')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')

case $event in
  # Claude puts the reason in .message. Codex has none on PermissionRequest, so
  # fall back to the tool description and then to the tool name — "waiting for
  # input" is true but tells you nothing about whether it is worth switching to.
  PermissionRequest|Notification)
    verb=$(printf '%s' "$payload" | jq -r '
      .message // .tool_input.description // .tool_name // "waiting for input"')
    if [[ $event == PermissionRequest ]]; then state=wait;  glyph='◆'
    else                                       state=ready; glyph='◆'; soft=1; fi ;;
  UserPromptSubmit) state=working; glyph=''  ; verb='working' ;;
  Stop)             state=ready;   glyph='✳' ; verb='finished' ;;
  *)                state='';      glyph='·' ; verb=$event ;;
esac

name=${cwd:t}
if [[ -n ${TMUX_PANE:-} && -n ${TMUX:-} ]]; then
  # session_attached, not just pane_active and window_active: those two say the
  # pane is the current one *within its own session*, which is true of every
  # pane in a session nobody is looking at. Without it, detaching and leaving an
  # agent running made Stop clear the state instead of setting ready — the exact
  # case ready exists for.
  info=$(tmux display -p -t "$TMUX_PANE" \
        '#{&&:#{session_attached},#{&&:#{pane_active},#{window_active}}}|#I.#P|#{@agent_state}|#{pane_title}')
  fg=${info%%|*}
  # A stale TMUX_PANE is not an error to tmux 3.7c: it exits 0 and expands the
  # format against empty fields, so testing the field beats testing the string.
  [[ $fg == [01] ]] || exit 0

  rest=${info#*|}; idx=${rest%%|*}
  rest=${rest#*|}; cur=${rest%%|*}
  title=${rest#*|}

  # `ready` means "finished and unread", so a turn that ends while you are
  # looking at the pane has already been read: clear it rather than set it.
  #
  # $soft is Notification and nothing else. Claude fires it 60s into an approval
  # that is still pending, so it must not overwrite a `wait` — but Stop must,
  # or granting an approval leaves the pane reading "Action Required" for good.
  if [[ -n $soft && $cur == wait ]]; then
    :
  elif [[ $state == ready && $fg == 1 ]]; then
    tmux set -pu -t "$TMUX_PANE" @agent_state
  elif [[ -n $state ]]; then
    tmux set -p -t "$TMUX_PANE" @agent_state "$state"
  fi
  tmux refresh-client -S

  [[ $fg == 1 ]] && exit 0                # foreground — you can see it
  [[ -n $glyph ]] || exit 0               # a prompt you just typed is not news

  # Both agents put decoration in the pane title; only the name is worth showing.
  # Claude prefixes ✳ and nothing else — its title never changes, so the spinner
  # frames an earlier version of this script stripped for do not exist. Codex
  # prefixes its run-state and, if `activity` is configured, a blinker ahead of
  # that; the [^|]* in the second strip covers whatever that blinker renders as.
  title=${title##✳[[:space:]]#}
  title=${title##(#b)*(Ready|Working|Action Required)[[:space:]]#\|[[:space:]]#}
  [[ -n $title ]] && name=$title

  # Four hazards, all of them the status bar's rather than a message's. '#'
  # introduces a format, and both halves reach the bar: the verb from the agent,
  # the name from the pane title. A newline is worse than it looks — tmux keeps
  # only the LAST line of a #() job's output, so one newline in a Codex tool
  # description drops the glyph, the agent, the window and the name, and the
  # highlight with them. '|' is the field separator status-tick.sh reads these
  # back with, and a Codex tool description is free to contain one. And the caps
  # keep the whole notice inside the 85 cells that status-right has left after
  # git, the clock and the date; nothing else trims it, and tmux trims from the
  # right, so an uncapped name eats the clock.
  # $name itself stays clean: the macOS banner is not a tmux format.
  esc=${${${${verb//$'\n'/ }//\#/\#\#}//\|//}:0:40}
  nesc=${${${${name//$'\n'/ }//\#/\#\#}//\|//}:0:20}
  # Not display-message; see the header of status-tick.sh. Pane-scoped rather
  # than global, because a single global slot meant the second of two agents
  # finishing at once erased the first with nothing to say it had. The pane that
  # owns the option is also the pane whose arrival clears it, so there is no
  # separate @notice_pane to keep in step.
  tmux set -p -t "$TMUX_PANE" @notice_txt " $glyph  $agent w$idx  $nesc — $esc " \; \
       set -p -t "$TMUX_PANE" @notice_name "$nesc" \; \
       set -p -t "$TMUX_PANE" @notice_glyph "$glyph" \; \
       set -p -t "$TMUX_PANE" @notice_at "$EPOCHSECONDS" \; \
       refresh-client -S
fi

[[ -n ${AGENT_NOTIFY_BANNER:-} ]] || exit 0
[[ -n $glyph ]] || exit 0

sound=${AGENT_NOTIFY_SOUND-Submarine}
if [[ -n $sound ]]; then
  osascript -e 'on run {t, s, m, snd}' \
            -e 'display notification m with title t subtitle s sound name snd' \
            -e 'end run' -- "$agent" "$name" "$verb" "$sound"
else
  osascript -e 'on run {t, s, m}' \
            -e 'display notification m with title t subtitle s' \
            -e 'end run' -- "$agent" "$name" "$verb"
fi

exit 0
