#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# tmux command cheatsheet — fuzzy-search every command, with a
# live man-page preview of the highlighted one.
#
# Bound to <prefix> F in ~/.tmux.conf via display-popup.
#
# Two modes in one file:
#   no args  → run fzf over `tmux list-commands`
#   one arg  → print that command's man entry (used as fzf's preview)
# fzf points --preview back at this script, so there's no second file
# and no nested-quote gymnastics.
# ─────────────────────────────────────────────────────────────

# Preview mode: full man entry for "$1", then a legend of its flags.
# Command entries start at a 5-space indent; prose is indented deeper,
# so the next 5-space line marks the end of this entry.
if [ -n "$1" ]; then
    cmd="$1"
    entry="$(man tmux | col -bx | awk -v c="$cmd" '
        $0 ~ ("^     " c " ")                                    { p = 1 }
        p && started && /^     [^ ]/ && $0 !~ ("^     " c " ")   { exit }
        p                                                        { print; started = 1 }
    ')"
    printf '%s\n' "$entry"

    # tmux documents flags inconsistently per command, but their MEANINGS are
    # conventional and reused everywhere. This legend decodes the opaque ones
    # (-bdfh…) the prose above leaves unexplained. A case-statement (not an
    # associative array) keeps it working on macOS's stock bash 3.2.
    flag_meaning() {
        case "$1" in
          a) echo "all / after / append" ;;
          A) echo "behave like attach if it exists" ;;
          b) echo "before — left of or above" ;;
          c) echo "start-directory (or client / command)" ;;
          C) echo "size / disable echo" ;;
          d) echo "detached — don't switch to it" ;;
          D) echo "down" ;;
          e) echo "set env var VAR=value" ;;
          E) echo "don't apply update-environment" ;;
          f) echo "full-size pane / client flags (varies)" ;;
          F) echo "format string (see FORMATS)" ;;
          g) echo "global option" ;;
          h) echo "horizontal split (left|right)" ;;
          H) echo "hexadecimal" ;;
          I) echo "forward stdin into the pane" ;;
          k) echo "kill/replace if it exists" ;;
          l) echo "size — lines/cols, % allowed (or: last)" ;;
          L) echo "left" ;;
          m) echo "marked target (see select-pane -m)" ;;
          n) echo "name (or: next)" ;;
          N) echo "note / numeric" ;;
          o) echo "only if unset / older" ;;
          p) echo "print / percentage" ;;
          P) echo "print info about the new pane/window" ;;
          q) echo "quiet — suppress errors" ;;
          r) echo "renumber / repeat / read-only (varies)" ;;
          R) echo "right" ;;
          s) echo "source — src-pane / src-window" ;;
          S) echo "server / start-line" ;;
          t) echo "target — dst / target-pane|window|session" ;;
          T) echo "title / tree" ;;
          u) echo "up / unset" ;;
          U) echo "up" ;;
          v) echo "vertical split (top|bottom)" ;;
          w) echo "window option" ;;
          x) echo "width / x-pos (or -x detach variant)" ;;
          y) echo "height / y-pos" ;;
          Z) echo "zoom the pane" ;;
          *) echo "—" ;;
        esac
    }

    # Synopsis = entry up to the alias line; grab every flag letter from its
    # [-xxxx] / [-x arg] groups and decode each.
    syn="$(printf '%s\n' "$entry" | awk '/\(alias:/{exit} {print}')"
    letters="$(printf '%s' "$syn" | grep -oE '\[-[A-Za-z]+' | sed 's/\[-//' | fold -w1 | sort -u)"

    if [ -n "$letters" ]; then
        DIM=$'\033[38;2;86;95;137m'; ACC=$'\033[38;2;122;162;247m'; OFF=$'\033[0m'
        printf '\n%s  flags — common meanings (exact behaviour in text above)%s\n' "$DIM" "$OFF"
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            printf '   %s-%s%s  %s\n' "$ACC" "$f" "$OFF" "$(flag_meaning "$f")"
        done <<< "$letters"
    fi
    exit 0
fi

# List mode: resolve our own absolute path so the preview self-call works
# regardless of how we were invoked (~ expansion, relative path, etc.).
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# Build a name→first-sentence map from the man page in a SINGLE pass, so each
# fzf row carries a description (scannable, and searchable by concept — typing
# "link" finds link-window, swap-window and move-window). Only the FIRST sentence
# is kept, so a concept named in a later one is not searchable. Command entries sit at a 5-space indent; the
# prose begins after the "(alias: …)" line, or — for alias-less commands — at
# the first capitalised, non-flag line.
dmap="$(mktemp)"
man tmux | col -bx | awk '
  /^     [^ ]/ { if(name&&desc) print name "\t" desc; name=$1; desc=""; mode="syn"; next }
  name=="" { next }
  /^      / { t=$0; sub(/^ +/,"",t);
     if (t ~ /^\(alias:/) { mode="desc"; next }
     if (mode=="syn") { if (t ~ /^[A-Z]/ && t !~ /^\[/ && t !~ /\]$/) mode="desc"; else next }
     if (mode=="desc" && desc !~ /\. /) desc=(desc==""?t:desc" "t); next }
  { if(name&&desc) print name "\t" desc; name="" }
  END { if(name&&desc) print name "\t" desc }
' > "$dmap"

# Authoritative command list = `tmux list-commands` (joins descriptions onto it;
# anything man didn't yield a sentence for falls back to its own flag synopsis).
# Tokyo Night --color matches the ~/.tmux.conf status bar.
tmux list-commands | sort | awk -v df="$dmap" '
  BEGIN{ while((getline l<df)>0){ i=index(l,"\t"); desc[substr(l,1,i-1)]=substr(l,i+1) } }
  { name=$1; syn=$0; sub(/^[^ ]+ +/,"",syn);
    d=(name in desc)?desc[name]:syn;
    if(match(d,/\. /)) d=substr(d,1,RSTART);
    printf "%-22s %s\n", name, d }
' \
  | fzf \
      --reverse --border=rounded --info=inline --cycle \
      --prompt='tmux ❯ ' \
      --pointer='▌' \
      --header='type to filter  ·  Enter / Esc to close' \
      --preview="$self {1}" \
      --preview-window='down:60%:wrap:border-top' \
      --color='fg:#c0caf5,bg:-1,hl:#7aa2f7,fg+:#c0caf5,bg+:#3b4261,hl+:#7dcfff,info:#565f89,border:#7aa2f7,prompt:#7aa2f7,pointer:#73daca,marker:#9ece6a,header:#565f89,gutter:-1'

rm -f "$dmap"
