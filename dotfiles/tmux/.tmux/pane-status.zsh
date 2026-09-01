# tmux pane status — publishes @ps_state / @ps_cmd / @ps_code / @ps_dur as tmux pane options.
# Rendered by window-status-format + pane-border-format in ~/.tmux.conf.
# Source from ~/.zshrc. Safe to source outside tmux (no-op).
#
#   TMUX_PS_NOTIFY_SEC   commands at least this slow that finish in a background
#                        pane raise a status-line nudge. 0 disables. (default 30)

[[ -n $TMUX ]] || return 0

autoload -Uz add-zsh-hook
zmodload zsh/datetime          # $EPOCHREALTIME — sub-second, monotonic enough here

typeset -g _ps_running=0
typeset -gF _ps_start=0

# 84ms / 2.4s / 47s / 3m08s / 1h04m — narrow enough for a pane border at any width.
# Sub-second gets milliseconds rather than a useless "0.0s": most commands you run
# are fast, and those are exactly the ones that would otherwise show nothing.
_ps_fmt() {
  local -F t=$1
  local -i s=$t
  if   (( t < 1 ));    then printf '%dms' $(( t * 1000 ))
  elif (( t < 10 ));   then printf '%.1fs' $t
  elif (( s < 60 ));   then printf '%ds' $s
  elif (( s < 3600 )); then printf '%dm%02ds' $((s/60)) $((s%60))
  else                      printf '%dh%02dm' $((s/3600)) $(((s%3600)/60))
  fi
}

_ps_preexec() {
  _ps_running=1
  _ps_start=$EPOCHREALTIME
  # newlines collapsed so a heredoc/multiline command can't wreck the status line
  tmux set -p -t "$TMUX_PANE" @ps_cmd "${1//$'\n'/ }" \; \
       set -p -t "$TMUX_PANE" @ps_state run \; \
       set -pu -t "$TMUX_PANE" @ps_dur \; \
       refresh-client -S 2>/dev/null
}

_ps_precmd() {
  local code=$?
  (( _ps_running )) || return 0   # bare Enter or shell startup — no command ran
  _ps_running=0

  local -F elapsed=$(( EPOCHREALTIME - _ps_start ))
  local dur=$(_ps_fmt $elapsed)
  local state=ok
  (( code )) && state=err

  tmux set -p -t "$TMUX_PANE" @ps_code "$code" \; \
       set -p -t "$TMUX_PANE" @ps_dur "$dur" \; \
       set -p -t "$TMUX_PANE" @ps_state "$state" \; \
       refresh-client -S 2>/dev/null

  local -i thresh=${TMUX_PS_NOTIFY_SEC:-30}
  (( thresh > 0 && elapsed >= thresh )) || return 0

  # Only nudge for panes you aren't looking at — otherwise you just watched it finish.
  local info
  info=$(tmux display -p -t "$TMUX_PANE" \
        '#{&&:#{pane_active},#{window_active}}|#I.#P' 2>/dev/null) || return 0
  [[ ${info%%|*} == 1 ]] && return 0

  # '#' is the format introducer; a command containing one would corrupt the message
  local cmd=${${(f)"$(tmux show -pv -t "$TMUX_PANE" @ps_cmd 2>/dev/null)"}//\#/\#\#}
  local glyph='✔'
  (( code )) && glyph="✘$code"
  # Not display-message; see the header of status-tick.sh.
  tmux set -g @notice " $glyph  w${info#*|}  ${cmd:0:48}  $dur " \; \
       set -g @notice_pane "$TMUX_PANE" \; \
       set -g @notice_at "$EPOCHSECONDS" \; \
       refresh-client -S 2>/dev/null
}

add-zsh-hook preexec _ps_preexec
add-zsh-hook precmd  _ps_precmd
