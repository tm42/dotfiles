#!/bin/zsh
# Claude Code hook → tmux status strip + macOS notification.
#
# Wired from ~/.claude/settings.json on two events:
#   Notification  Claude wants permission, or has sat idle ≥60s waiting on you
#   Stop          Claude finished its turn
#
# Fires only when the Claude pane is in the background — if you're looking at it
# you already know. Always exits 0: a hook that errors would nag Claude, not you.
#
#   CLAUDE_NOTIFY_SOUND   macOS alert sound name, or "" for silent (default Submarine)

emulate -L zsh
setopt no_unset extended_glob     # extended_glob: the ##pattern strip below needs it
exec 2>/dev/null

payload=$(cat)
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // "Stop"')
message=$(printf '%s' "$payload" | jq -r '.message // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')

case $event in
  Notification) glyph='◆'; verb=${message:-waiting for input} ;;
  Stop)         glyph='✳'; verb='finished' ;;
  *)            glyph='·'; verb=$event ;;
esac

# Claude writes "<status glyph> <session name>" into the pane title; the session
# name is the only part worth showing, and it beats a bare pane index.
name=${cwd:t}
if [[ -n ${TMUX_PANE:-} && -n ${TMUX:-} ]]; then
  info=$(tmux display -p -t "$TMUX_PANE" \
        '#{&&:#{pane_active},#{window_active}}|#I.#P|#{pane_title}')
  [[ -n $info ]] || exit 0
  [[ ${info%%|*} == 1 ]] && exit 0        # foreground — you can see it

  rest=${info#*|}
  idx=${rest%%|*}
  title=${rest#*|}
  # strip Claude's leading status glyph, keep the session name
  title=${title##[✳◐⠿✻✽·]#[[:space:]]#}
  [[ -n $title ]] && name=$title

  esc=${${verb//\#/\#\#}:0:60}
  tmux display-message -d 5000 " $glyph  claude w$idx  $name — $esc "
fi

sound=${CLAUDE_NOTIFY_SOUND-Submarine}
if [[ -n $sound ]]; then
  osascript -e 'on run {t, s, m, snd}' \
            -e 'display notification m with title t subtitle s sound name snd' \
            -e 'end run' -- "Claude Code" "$name" "$verb" "$sound"
else
  osascript -e 'on run {t, s, m}' \
            -e 'display notification m with title t subtitle s' \
            -e 'end run' -- "Claude Code" "$name" "$verb"
fi

exit 0
