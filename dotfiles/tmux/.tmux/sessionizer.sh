#!/bin/zsh
# fzf project switcher — pick a directory, attach-or-create a session named after it.
# Bound to M-o in ~/.tmux.conf; runs inside display-popup -E.
#
# Roots come from $TMUX_SESSIONIZER_ROOTS, a colon-separated list, exported from
# your shell rc. Each root is scanned at depth 1 AND depth 2, so both
# ~/code/apps and ~/code/apps/thing are reachable:
#
#   export TMUX_SESSIONIZER_ROOTS="$HOME/code:$HOME/work"
#
# Unset, it falls back to whichever of the usual suspects actually exist.
# $TMUX_SESSIONIZER_EXTRA (same format) adds single directories that are NOT
# scanned for children — config dirs, $HOME itself, and so on.

emulate -L zsh
setopt null_glob extended_glob

# Read machine.zsh directly rather than relying on the environment. tmux runs a
# display-popup child with the SERVER's environment, never the calling pane's, so
# a variable exported by your shell rc is invisible here until the server is
# restarted — and it fails silently, because the fallback $extras below always
# exist and fzf opens with them instead of erroring.
[[ -f ~/.config/punto/machine.zsh ]] && source ~/.config/punto/machine.zsh

if [[ -n ${TMUX_SESSIONIZER_ROOTS:-} ]]; then
  roots=( ${(s.:.)TMUX_SESSIONIZER_ROOTS} )
else
  roots=( ~/projects(N/) ~/code(N/) ~/dev(N/) ~/src(N/) ~/work(N/) ~/repos(N/) )
fi

if [[ -n ${TMUX_SESSIONIZER_EXTRA:-} ]]; then
  extras=( ${(s.:.)TMUX_SESSIONIZER_EXTRA} )
else
  extras=( ~/.config(N/) ~ )
fi

dirs=()
for r in $roots; do
  [[ -d $r ]] || continue
  # (-/N), not (/N): the bare / qualifier matches real directories only, so a
  # project reached by a symlink is silently absent from the picker.
  dirs+=( $r/*(-/N) $r/*/*(-/N) )
done
dirs+=( $extras )

# already-open sessions float to the top, so switching back is one keystroke
open=( ${(f)"$(tmux list-sessions -F '#{session_path}' 2>/dev/null)"} )
ordered=( $open $dirs )
ordered=( ${(u)ordered} )

(( $#ordered )) || { print -u2 "sessionizer: no directories — set TMUX_SESSIONIZER_ROOTS"; sleep 2; exit 0 }

# BSD ls colours with -G, GNU with --color; probing once is cheaper than guessing
if ls --color=always / >/dev/null 2>&1; then
  preview='ls -A --color=always {} 2>/dev/null | head -60'
else
  preview='CLICOLOR_FORCE=1 ls -AG {} 2>/dev/null | head -60'
fi

sel=$(print -rl -- $ordered | fzf \
  --prompt='  project  ' \
  --height=100% --border=none --reverse --info=inline \
  --preview=$preview \
  --preview-window='right:45%:border-left') || exit 0

[[ -n $sel && -d $sel ]] || exit 0

# session names can't contain '.' or ':' — tmux parses those as target separators
name=${${sel:t}//[.: ]/_}
[[ -n $name ]] || name=home

tmux has-session -t "=$name" 2>/dev/null || tmux new-session -ds "$name" -c "$sel"
tmux switch-client -t "=$name"
