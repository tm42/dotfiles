#!/bin/bash
# shellcheck disable=SC2059,SC1083,SC2001
#   SC2059 (variables in a printf format string): every one of these formats is
#     built from ANSI colour escapes, which contain no % — and line 231 relies on
#     printf interpreting \x escapes, so a blanket '%s' rewrite would break it.
#   SC1083 (literal brace): @{upstream} is git revision syntax, not an expansion.
#   SC2001 (sed for a simple replacement): the sed reads better than the
#     parameter-expansion form and runs once per prompt, not in a loop.

# Agnoster-style status line for Claude Code
# With proper powerline arrows between segments

# Read JSON input
input=$(cat)

# Palette: "teal native", anchored on #002b36 — the ground .tmux.conf:153 paints
# on the active pane, which is what this renders on under tmux, terminal setting
# or not.
# Identity segments (host/venv/path) share one desaturated teal family; saturated
# colour is reserved for the three gauges, each a four-step ramp in a single hue.
# Requires CLAUDE_CODE_TMUX_TRUECOLOR=1 under tmux — Claude Code otherwise clamps
# 24-bit to the 256 cube and these collapse into each other.

# Background colors
BG_BLUE="\033[48;2;107;157;175m"   # #6b9daf  host
BG_VENV="\033[48;2;94;124;135m"    # #5e7c87  venv
BG_CYAN="\033[48;2;46;96;114m"     # #2e6072  path — was ANSI 44, the one theme-dependent colour
BG_GREEN="\033[48;2;175;215;175m"  # #afd7af  git clean, xterm 151 kept verbatim
BG_YELLOW="\033[48;2;255;255;215m" # #ffffd7  git dirty, xterm 230 kept verbatim

# Foreground colors (for arrows)
FG_BLUE="\033[38;2;107;157;175m"
FG_VENV="\033[38;2;94;124;135m"
FG_CYAN="\033[38;2;46;96;114m"
FG_GREEN="\033[38;2;175;215;175m"
FG_YELLOW="\033[38;2;255;255;215m"

# Text colors
BLACK="\033[38;2;13;13;13m"        # #0d0d0d, the ink for every light segment
PAPER="\033[38;2;244;244;244m"     # #f4f4f4, for the path segment only
RESET="\033[0m"

# Powerline arrow (Unicode U+E0B0, UTF-8: EE 82 B0)
SEP=$'\xee\x82\xb0'

# Get current directory, truncate to last 3 path components
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
display_dir=$(echo "$current_dir" | sed "s|^$HOME|~|")
# Truncate: if more than 3 components, show .../last/three/parts
IFS='/' read -ra _parts <<< "$display_dir"
_nonempty=()
for _p in "${_parts[@]}"; do [ -n "$_p" ] && _nonempty+=("$_p"); done
_n=${#_nonempty[@]}
if [ "$_n" -gt 3 ]; then
    display_dir=".../${_nonempty[$((_n-3))]}/${_nonempty[$((_n-2))]}/${_nonempty[$((_n-1))]}"
fi

# --- LINE 1: user@host  directory  [git] ---

# User and host segment (blue background, white text)
user=$(whoami)
host=$(hostname -s)
printf "${BG_BLUE}${BLACK} %s@%s " "$user" "$host"

# Venv segment (metallic grey, between host and path)
venv_name=""
if [ -n "$VIRTUAL_ENV" ]; then
    # Named venv (e.g. ~/myproject-env) → show its name; .venv → show parent dir
    vn=$(basename "$VIRTUAL_ENV")
    if [ "$vn" = ".venv" ]; then
        venv_name=$(basename "$(dirname "$VIRTUAL_ENV")")
    else
        venv_name="$vn"
    fi
elif [ -d "$current_dir/.venv" ]; then
    venv_name=$(basename "$current_dir")
fi

if [ -n "$venv_name" ]; then
    # Arrow: blue → grey
    printf "${BG_VENV}${FG_BLUE}${SEP}${BLACK}"
    # Venv name
    printf "  %s " "$venv_name"
    # Arrow: grey → cyan
    printf "${BG_CYAN}${FG_VENV}${SEP}${PAPER}"
else
    # Arrow: blue → cyan (no venv)
    printf "${BG_CYAN}${FG_BLUE}${SEP}${PAPER}"
fi

# Directory segment (cyan background, black text)
printf " %s " "$display_dir"

# Git segment (if in git repo)
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$current_dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || \
             git -C "$current_dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null || \
             echo "unknown")

    # Powerline branch char, varies by ahead/behind status
    PL_BRANCH=$'\xee\x82\xa0'
    ahead=$(git -C "$current_dir" --no-optional-locks log --oneline @{upstream}.. 2>/dev/null)
    behind=$(git -C "$current_dir" --no-optional-locks log --oneline ..@{upstream} 2>/dev/null)
    if [ -n "$ahead" ] && [ -n "$behind" ]; then
        PL_BRANCH=$'\xe2\x87\x85'
    elif [ -n "$ahead" ]; then
        PL_BRANCH=$'\xe2\x86\xb1'
    elif [ -n "$behind" ]; then
        PL_BRANCH=$'\xe2\x86\xb0'
    fi

    if git -C "$current_dir" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null; then
        # Clean repo - green
        printf "${BG_GREEN}${FG_CYAN}${SEP}${BLACK} ${PL_BRANCH} %s " "$branch"
        printf "${RESET}${FG_GREEN}${SEP}${RESET}"
    else
        # Dirty repo - yellow
        printf "${BG_YELLOW}${FG_CYAN}${SEP}${BLACK} ${PL_BRANCH} ± %s " "$branch"
        printf "${RESET}${FG_YELLOW}${SEP}${RESET}"
    fi
else
    # No git - close cyan segment
    printf "${RESET}${FG_CYAN}${SEP}${RESET}"
fi

# --- LINE 2: context load ---
printf "\n"

# Darkness ladder: model, effort, 1m. Cool blue-slate, three rungs at L* 26 / 38 / 74,
# climbing towards the ctx bands (L* 63-84) rather than colliding with them.
# Claude Code's effort colours are built for a dark ground — on white they collapse
# to 1.5-2.3 contrast; on rung 2 they run 3.05-4.58.
BG_MODEL="\033[48;2;29;66;79m"     # #1d424f  rung 1, L* 26 — clears the L* 15 ground
FG_MODEL="\033[38;2;29;66;79m"
BG_EFFORT="\033[48;2;48;95;113m"   # #305f71  rung 2, L* 38
FG_EFFORT="\033[38;2;48;95;113m"
BG_CHERRY="\033[48;2;161;186;195m" # #a1bac3  rung 3, L* 74
FG_CHERRY="\033[38;2;161;186;195m"
CORAL="\033[38;2;153;59;44m"       # #993b2c, 3.42 on rung 3
CRIMSON_1M="\033[38;2;163;0;0m"    # #a30000, 4.04, for the clamped badge

# Parse model from input
model_raw=$(echo "$input" | jq -r '.model // .model_id // ""' | tr '[:upper:]' '[:lower:]')
if echo "$model_raw" | grep -qi "haiku"; then
    model_short="haiku"; MODEL_TEXT="\033[38;2;87;206;186m"
elif echo "$model_raw" | grep -qi "opus"; then
    model_short="opus";  MODEL_TEXT="\033[38;2;233;161;98m"
elif echo "$model_raw" | grep -qi "fable"; then
    model_short="fable"; MODEL_TEXT="\033[38;2;218;164;218m"
else
    # unrecognised models land here — check this branch first when the label looks wrong
    model_short="sonnet"; MODEL_TEXT="\033[38;2;232;196;49m"
fi
# Context load segment. One jq call for percent, effective window size and effort.
IFS='|' read -r percent ctx_size effort_level <<< "$(echo "$input" | jq -r '
    [(.context_window.used_percentage // 0 | floor),
     (.context_window.context_window_size // 0),
     (.effort.level // "")] | join("|")')"
effort_level=${effort_level//%/}

# If jq is missing or the payload is malformed, $percent is empty — and an empty
# string fails every numeric test below, falling through to the >T3 branch and
# reporting a confident alarm-red "ctx: 0%". Blank it deliberately instead, so
# the segment says "?" rather than a number nobody should trust.
case $percent in ''|*[!0-9]*) percent="" ;; esac

# 1m badge tracks the EFFECTIVE window, not the model string. Claude Code can serve
# a [1m] model against a 200k window (the long-context credit clamp), and it can drop
# the [1m] suffix on its own when the subscription/credit read comes back empty — so
# keying off the id alone makes the badge flicker for reasons unrelated to selection.
model_id_1m=""
echo "$model_raw" | grep -q '\[1m\]' && model_id_1m="1"
if [ "${ctx_size:-0}" -ge 400000 ]; then
    model_1m="1"      # really running a 1M window
    ctx_clamped=""
elif [ -n "$model_id_1m" ]; then
    model_1m=""       # 1m model, 200k window — say so rather than silently vanish
    ctx_clamped="1"
else
    model_1m=""
    ctx_clamped=""
fi

# Context-specific colors: Airy Cloud pastel palette
BG_LAVENDER="\033[48;2;207;208;229m"  # #cfd0e5  periwinkle
FG_LAVENDER="\033[38;2;207;208;229m"
BG_SEAFOAM="\033[48;2;141;206;179m"   # #8dceb3  seafoam
FG_SEAFOAM="\033[38;2;141;206;179m"
BG_BUTTER="\033[48;2;214;164;119m"    # #d6a477  amber
FG_BUTTER="\033[38;2;214;164;119m"
BG_SALMON="\033[48;2;226;123;112m"    # #e27b70  coral
FG_SALMON="\033[38;2;226;123;112m"

# Context-load color bands. used_percentage is normalised to the active window,
# but a 1m window's effective attention degrades long before the tokens fill —
# so 1m escalates colour EARLIER (tighter bands) than the standard window.
# T1: lavender→seafoam, T2: seafoam→butter, T3: butter→salmon.
if [ -n "$model_1m" ]; then
    T1=10; T2=20; T3=40
else
    T1=20; T2=40; T3=60
fi

# Choose color based on percentage
if [ -z "$percent" ]; then
    CTX_BG="$BG_LAVENDER"; CTX_FG="$FG_LAVENDER"; CTX_TEXT="$BLACK"
elif [ "$percent" -lt "$T1" ]; then
    CTX_BG="$BG_LAVENDER"; CTX_FG="$FG_LAVENDER"; CTX_TEXT="$BLACK"
elif [ "$percent" -lt "$T2" ]; then
    CTX_BG="$BG_SEAFOAM"; CTX_FG="$FG_SEAFOAM"; CTX_TEXT="$BLACK"
elif [ "$percent" -le "$T3" ]; then
    CTX_BG="$BG_BUTTER"; CTX_FG="$FG_BUTTER"; CTX_TEXT="$BLACK"
else
    CTX_BG="$BG_SALMON"; CTX_FG="$FG_SALMON"; CTX_TEXT="$BLACK"
fi

# Render model segment
printf "${BG_MODEL}${MODEL_TEXT} %s " "$model_short"
PREV_FG="$FG_MODEL"

# Effort segment. Colours are Claude Code's own /effort levels, verbatim, with its
# glyph ramp. max rotates xhigh/red/low with a shine in the selector; the statusline
# only redraws on events, so spread those across the characters rather than pretend
# to animate. ultracode is indistinguishable here — it serialises to xhigh.
if [ -n "$effort_level" ]; then
    XH="\033[38;2;176;176;242m"      # xhigh
    MD="\033[38;2;97;209;134m"       # medium
    LO="\033[38;2;246;206;6m"        # low
    HI="\033[38;2;150;212;243m"      # high
    RD="\033[38;2;240;147;119m"      # the red in max's rotation
    case "$effort_level" in
        low)    EFF_TXT="${LO}\xe2\x97\x8b low" ;;
        medium) EFF_TXT="${MD}\xe2\x97\x90 medium" ;;
        high)   EFF_TXT="${HI}\xe2\x97\x8f high" ;;
        xhigh)  EFF_TXT="${XH}\xe2\x97\x89 xhigh" ;;
        max)    EFF_TXT="${XH}\xe2\x97\x88 ${RD}m${LO}a${XH}x" ;;
        *)      EFF_TXT="${HI}\xe2\x97\x8f ${effort_level}" ;;
    esac
    printf "${BG_EFFORT}${PREV_FG}${SEP} ${EFF_TXT} "
    PREV_FG="$FG_EFFORT"
fi

if [ -n "$model_1m" ]; then
    printf "${BG_CHERRY}${PREV_FG}${SEP}${CORAL} 1m "
    PREV_FG="$FG_CHERRY"
elif [ -n "$ctx_clamped" ]; then
    # Model is [1m] but the served window is 200k — long-context credit clamp.
    printf "${BG_CHERRY}${PREV_FG}${SEP}${CRIMSON_1M} 1m\xe2\x9c\x97 "
    PREV_FG="$FG_CHERRY"
fi

# Arrow: previous → ctx
ctx_label="${percent}%"; [ -z "$percent" ] && ctx_label="?"
printf "${CTX_BG}${PREV_FG}${SEP}${CTX_TEXT} ctx: %s " "$ctx_label"

# Rate-limit segments: % used + when the window resets.
# Showing % (static between renders) rather than time-remaining (decays silently
# while statusline isn't re-rendered). Both absent for non-Pro/Max or pre-first-response.
session_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d'.' -f1)
session_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_used=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d'.' -f1)
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Gold ramp — 5-hour segment. Pale cream to deep amber, so filling the window reads
# as warming up. Yellow against the week segment blue is the widest hue separation
# available while keeping every background light enough for black text.
# 230 is also the git-dirty background, but the two segments sit at opposite ends
# of the bar and git-dirty is transient, so the collision is accepted.
BG_GOLD1="\033[48;2;244;234;213m"; FG_GOLD1="\033[38;2;244;234;213m"  # #f4ead5  <25%
BG_GOLD2="\033[48;2;238;212;165m"; FG_GOLD2="\033[38;2;238;212;165m"  # #eed4a5  25-49%
BG_GOLD3="\033[48;2;234;185;101m"; FG_GOLD3="\033[38;2;234;185;101m"  # #eab965  50-74%
BG_GOLD4="\033[48;2;235;154;23m";  FG_GOLD4="\033[38;2;235;154;23m"   # #eb9a17  >=75%

# Blue ramp — week segment. Same 25/50/75 thresholds as gold, same pale-to-deep
# movement, so the two bars are read the same way and differ only in hue.
# 75 is about as deep as this can go and still take black text comfortably.
BG_ICE1="\033[48;2;217;239;244m"; FG_ICE1="\033[38;2;217;239;244m"  # #d9eff4  <25%
BG_ICE2="\033[48;2;180;222;237m"; FG_ICE2="\033[38;2;180;222;237m"  # #b4deed  25-49%
BG_ICE3="\033[48;2;137;201;233m"; FG_ICE3="\033[38;2;137;201;233m"  # #89c9e9  50-74%
BG_ICE4="\033[48;2;97;179;234m";  FG_ICE4="\033[38;2;97;179;234m"   # #61b3ea  >=75%

pick_color() {
    local pct=$1
    if   [ "$pct" -lt 25 ]; then echo "$BG_GOLD1|$FG_GOLD1"
    elif [ "$pct" -lt 50 ]; then echo "$BG_GOLD2|$FG_GOLD2"
    elif [ "$pct" -lt 75 ]; then echo "$BG_GOLD3|$FG_GOLD3"
    else                         echo "$BG_GOLD4|$FG_GOLD4"
    fi
}

pick_color_ice() {
    local pct=$1
    if   [ "$pct" -lt 25 ]; then echo "$BG_ICE1|$FG_ICE1"
    elif [ "$pct" -lt 50 ]; then echo "$BG_ICE2|$FG_ICE2"
    elif [ "$pct" -lt 75 ]; then echo "$BG_ICE3|$FG_ICE3"
    else                         echo "$BG_ICE4|$FG_ICE4"
    fi
}

PREV_FG="$CTX_FG"

# Format an epoch second. BSD date reads -r as seconds-since-epoch; GNU coreutils
# reads -r as a FILE to take the timestamp from, so it errors and the segment
# renders " 47% >> " with nothing after the arrow. Probe once rather than guess,
# the same way sessionizer.sh probes ls.
if date -r 0 "+%H" >/dev/null 2>&1; then
    epoch_fmt() { date -r "$1" "+$2"; }          # BSD / macOS
else
    epoch_fmt() { date -d "@$1" "+$2"; }         # GNU
fi

if [ -n "$session_used" ] && [ -n "$session_reset" ]; then
    session_when=$(epoch_fmt "$session_reset" "%H:%M")
    IFS='|' read -r S_BG S_FG <<< "$(pick_color "$session_used")"
    printf "${S_BG}${PREV_FG}${SEP}${BLACK} %d%% >> %s " "$session_used" "$session_when"
    PREV_FG="$S_FG"
fi

if [ -n "$week_used" ] && [ -n "$week_reset" ]; then
    # Weekly window resets on a fixed weekday — show that (lowercase 3-letter)
    # rather than the date, which carries no extra signal. macOS date has no
    # lowercase token, so %a ("Mon") is piped through tr.
    week_when=$(epoch_fmt "$week_reset" "%a" | tr '[:upper:]' '[:lower:]')
    IFS='|' read -r W_BG W_FG <<< "$(pick_color_ice "$week_used")"
    printf "${W_BG}${PREV_FG}${SEP}${BLACK} %d%% >> %s " "$week_used" "$week_when"
    PREV_FG="$W_FG"
fi

printf "${RESET}${PREV_FG}${SEP}${RESET}"
