#!/bin/zsh
# status-bar git segment for $1 (the active pane's cwd). Prints nothing outside a repo.
# Re-runs on every status redraw (status-interval 5), so it stays deliberately cheap:
# one rev-parse to bail early, then one porcelain scan.
#
# Caveat: `git status` on a very large or cold repo can take longer than the redraw
# interval. tmux runs #() in the background and keeps the last output, so a slow repo
# shows a stale branch rather than stalling the bar.

emulate -L zsh

d=$1
[[ -d $d ]] || exit 0
cd -- $d 2>/dev/null || exit 0

[[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == true ]] || exit 0

b=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) \
  || b=$(git rev-parse --short HEAD 2>/dev/null) \
  || exit 0

n=$(git status --porcelain 2>/dev/null | grep -c .)

if (( n )); then
  printf ' %s ●%d ' "$b" "$n"
else
  printf ' %s ' "$b"
fi
