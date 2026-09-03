#!/usr/bin/env python3
"""debug — which link in the agent-notification chain just broke?

MUTATES. Unlike check.py, this one creates a throwaway tmux window, sets pane
options, temporarily appends to status-right, and swaps a symlink. Every one of
those is undone before it exits — including on an exception or Ctrl-C — except
`tap on`, which is the one subcommand meant to leave a change in place until
`tap off` runs. `inspect` is the exception in the other direction: it only ever
reads, which is what makes it the safe thing to point at a pane that is stuck
right now. Running status-tick.sh by hand, as `chain` does, would sweep the very
notice you are trying to look at.

The chain it inspects, in order: an agent (Claude, Codex, opencode) fires a
hook -> ~/.tmux/agent-notify.sh sets @agent_state and four @notice_* pane
options -> ~/.tmux/status-tick.sh reads those on every status-right redraw and
renders the bar. Neither script is changed here — this walks it and drives it.

Stdlib only, Python 3.9, the same floor as check.py. Shells out to tmux, zsh
and jq rather than reimplementing any of them: the thing under test is the
real scripts, so a second implementation of their logic would pass while they
fail.

    ./debug.py inspect [WINDOW]              # read-only: why does that tab say that?
    ./debug.py chain [--agent claude|codex|opencode] [--target WINDOW]
    ./debug.py watch [--interval SECONDS] [--log PATH]
    ./debug.py mark [--log PATH] [TEXT ...]
    ./debug.py tap on|off|status
    ./debug.py --socket NAME <subcommand>   # talk to a different tmux server;
                                            # must come before the subcommand,
                                            # same placement as tmux's own -L.
                                            # For testing against a scratch
                                            # server instead of the one three
                                            # live agents depend on.

Logs land in ~/punto-debug/ — one directory to name in a sentence and delete
in one command. Not inside this checkout: punto is a public repo, and these
logs can carry the text of your prompts.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent
HOME = Path.home()
NOTIFY_LINK = HOME / ".tmux" / "agent-notify.sh"
STATUS_TICK_LINK = HOME / ".tmux" / "status-tick.sh"
REAL_NOTIFY = REPO / "dotfiles" / "tmux" / ".tmux" / "agent-notify.sh"
REAL_STATUS_TICK = REPO / "dotfiles" / "tmux" / ".tmux" / "status-tick.sh"

LOGDIR = HOME / "punto-debug"
WATCH_LOG = LOGDIR / "watch.log"
TAP_LOG = LOGDIR / "tap.log"
WRAPPER_PATH = LOGDIR / "agent-notify-tap.sh"

BOLD, DIM, GREEN, YELLOW, RED, OFF = (
    "\033[1m", "\033[2m", "\033[32m", "\033[33m", "\033[31m", "\033[0m")
if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
    BOLD = DIM = GREEN = YELLOW = RED = OFF = ""

_fail = 0
SOCKET = None  # set from --socket before any subcommand runs


def say(m):
    print(f"\n{BOLD}{m}{OFF}")


def ok(m):
    print(f"  {GREEN}✔{OFF} {m}")


def warn(m):
    print(f"  {YELLOW}!{OFF} {m}")


def bad(m):
    global _fail
    _fail += 1
    print(f"  {RED}✘{OFF} {m}")


def tmux(*args, env=None, input=None) -> subprocess.CompletedProcess:
    """Every tmux call goes through here so --socket only has to be threaded
    once. check=False throughout: a failing tmux command is itself the
    diagnostic, not a bug in this script, so callers branch on returncode."""
    cmd = ["tmux"]
    if SOCKET:
        cmd += ["-L", SOCKET]
    cmd += list(args)
    return subprocess.run(cmd, env=env, input=input, capture_output=True, text=True)


class ProbeFailed(Exception):
    """A probe could not be set up. Raised rather than returned so the caller's
    `finally` still tears down whatever was already created."""


# Everything status-tick.sh touches. It is not scoped to one pane — it sweeps
# `list-panes -a` — so these are what has to be put back afterwards.
SWEPT = ("@agent_state", "@notice_txt", "@notice_name", "@notice_glyph",
         "@notice_at", "@agent_screen", "@agent_screen_at")


# Separators for every `list-panes -F` read in this file. Not "|" and not a
# newline, which is what a tmux format is usually joined and split on, because
# both occur in the data: @notice_txt and @notice_name carry text an agent
# wrote. Measured, both on a scratch server:
#   a "|" in @notice_txt shifted every field after it one place left, and the
#     restore then wrote a non-numeric string into @notice_at on a real pane —
#     which status-tick.sh evaluates arithmetically on every redraw;
#   a newline in @notice_txt ended the record early, so the fields after it read
#     as unset and `inspect` reported, in detail, a fault that had not happened.
# Neither byte can appear in tmux's own output for these formats.
US, RS = "\x1f", "\x1e"


def panes_format(*fields: str) -> str:
    """A `list-panes -F` format that can be parsed back unambiguously."""
    return US.join("#{" + f + "}" for f in fields) + RS


def panes_rows(stdout: str, n: int) -> list:
    """The records of such a read, each one exactly n fields.

    Raises rather than padding or dropping. A short record used to be padded
    with empty strings, and empty is a meaningful value here — it is what an
    unset option looks like — so the padding did not read as missing data, it
    read as a pane whose notice had been cleared."""
    rows = []
    for record in stdout.split(RS):
        record = record.strip("\n")
        if not record:
            continue
        vals = record.split(US)
        if len(vals) != n:
            raise ProbeFailed(f"tmux returned {len(vals)} fields where {n} were "
                              f"asked for: {record!r}")
        rows.append(vals)
    return rows


def snapshot_options() -> dict:
    """Every pane's swept options, keyed by pane id.

    Empty on any failure, including a record it cannot parse: restore_options
    is called from a `finally`, and a raise there would replace whatever sent
    the probe there in the first place."""
    r = tmux("list-panes", "-a", "-F", panes_format("pane_id", *SWEPT))
    if r.returncode != 0:
        return {}
    try:
        return {row[0]: row[1:] for row in panes_rows(r.stdout, len(SWEPT) + 1)}
    except ProbeFailed:
        return {}


def restore_options(before: dict, skip: str) -> int:
    """Put back anything the sweep changed on a pane that is not the probe.

    Running the real status-tick.sh is the whole point of the probe — a second
    implementation of its logic would pass while it fails. But it clears every
    pane whose notice is older than its HOLD, and on the machine you are
    debugging the sweep is the thing that is not running, so those notices have
    been piling up and are the evidence `watch` exists to collect. Undoing the
    collateral leaves the reading intact and the evidence where it was.

    An option that was empty is unset rather than set to "", because tmux tells
    the two apart and status-tick.sh's own `[[ -n $nat ]]` test does too."""
    after = snapshot_options()
    restored = 0
    for pane_id, old_vals in before.items():
        if pane_id == skip or pane_id not in after:
            continue
        for name, was, now in zip(SWEPT, old_vals, after[pane_id]):
            if was == now:
                continue
            if was:
                tmux("set", "-p", "-t", pane_id, name, was)
            else:
                tmux("set", "-pu", "-t", pane_id, name)
            restored += 1
    return restored


def tmux_env_for_pane(pane_id: str) -> dict:
    """agent-notify.sh and status-tick.sh call bare `tmux`, not this script's
    -L-aware wrapper — they run on the machine being debugged, unmodified, so
    they resolve their server the way tmux always does: from $TMUX. Building
    that value here is what lets --socket reach a scratch server at all."""
    r = tmux("display", "-p", "-t", pane_id, "#{socket_path}|#{pid}|#{session_id}")
    parts = r.stdout.strip().split("|")
    if r.returncode != 0 or len(parts) != 3:
        raise ProbeFailed(f"could not read the server address for {pane_id}: "
                          f"{r.stderr.strip() or r.stdout.strip() or 'no output'}")
    sock_path, pid, sess_id = parts
    env = dict(os.environ)
    env["TMUX"] = f"{sock_path},{pid},{sess_id.lstrip('$')}"
    env["TMUX_PANE"] = pane_id
    return env


# ── chain ────────────────────────────────────────────────────


def pick_session():
    """Returns (session_id, caveat). caveat is None when a client is attached
    to the session chosen — only then does session_attached read nonzero and
    the foreground test in step 5 mean anything. Prefers an attached session
    over guessing; refuses to pick among several unattached ones, because a
    wrong guess there produces readings that look valid and are not.

    The id ($0) and not the name, because `-t <name>` is ambiguous: tmux reads
    a target that looks like a number as a window index in the current session.
    A session named "0" — which is what `tmux new-session` gives you when you
    never name one — turned `new-window -t 0` into "create window failed:
    index 0 in use". A session id can never be read as an index.

    session_attached is a count of clients, not a flag, so it is compared
    against "0" rather than against "1": a session you are attached to from
    two terminals reads 2, and testing for "1" dropped it."""
    r = tmux("list-sessions", "-F", "#{session_id}|#{session_attached}")
    if r.returncode != 0:
        return None, r.stderr.strip() or "no tmux server on this socket"
    rows = [ln.split("|") for ln in r.stdout.splitlines() if ln]
    if not rows:
        return None, "no sessions on this socket"
    attached = [sid for sid, att in rows if att != "0"]
    if attached:
        return attached[0], None
    if len(rows) == 1:
        return rows[0][0], "no client is attached — session_attached will read 0, so the background test below cannot mean anything"
    return None, f"{len(rows)} sessions on this socket, none with a client attached — re-run with an attached client, or reduce to one session"


def resolve_target_pane(target: str) -> str:
    """A window or pane the caller named — "3", "0:3", "%12", "3.1" — down to
    one pane id. tmux resolves it, not this function, so anything tmux accepts
    works and nothing here has to know the syntax. The first pane of a window
    with several is the one probed, and the caller prints what it resolved to
    so a target that landed somewhere unintended is visible rather than silent."""
    r = tmux("list-panes", "-t", target, "-F", "#{pane_id}")
    if r.returncode != 0 or not r.stdout.strip():
        raise ProbeFailed(f"--target {target!r}: {r.stderr.strip() or 'matched no pane'}")
    return r.stdout.split()[0]


def run_probe(session: str, event: str, message: str, agent: str, expect_state: str,
              expect_notice: bool, why_no_notice: str = "", target: str = None) -> None:
    """One throwaway window, one synthetic hook payload, one comparison that
    matters: whether status-tick.sh's own rendering agrees with what
    agent-notify.sh just set. Reporting the two readings separately — as an
    earlier version of this did — let a genuinely empty sweep pass silently
    whenever the notice was also, correctly, empty; the comparison is what
    catches an empty sweep sitting next to a notice that WAS set, which is
    the actual fault this tool exists to find. Torn down before returning, so
    two probes in the same chain() run never see each other's notice."""
    say(f"probe: {event} as {agent}")
    # window_id is bound before the try and the kill is guarded on it, so a
    # signal delivered between `new-window` returning and the try being entered
    # cannot leave the window behind. That gap is microscopic and it is also
    # the only one: current.toml makes "no throwaway window survives an
    # interrupt" a property, and a property with a hole in it is not one.
    window_id = None
    borrowed = None      # (pane_id, options as they were) when --target lent us one
    try:
        if target:
            # A window you already have and are willing to have written on, for
            # the case where creating one is what fails. Its options go back the
            # way `finally` puts a created window back: killed there, restored
            # here, and the probe itself is identical either way.
            pane_id = resolve_target_pane(target)
            where = tmux("display", "-p", "-t", pane_id,
                         "#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}")
            ok(f"probing in {where.stdout.strip()} ({pane_id}), lent by --target {target}")
            borrowed = (pane_id, snapshot_options().get(pane_id))
        else:
            # -a, and the session by id: without -a tmux wants the target
            # window's own index, which is by definition in use.
            r = tmux("new-window", "-d", "-a", "-t", f"{session}:", "-P", "-F", "#{window_id}")
            if r.returncode != 0:
                bad(f"could not create a probe window: {r.stderr.strip()} — "
                    f"if a window is easier to lend than to create, ./debug.py chain --target <window>")
                return
            window_id = r.stdout.strip()
            r = tmux("list-panes", "-t", window_id, "-F", "#{pane_id}")
            pane_id = r.stdout.strip().splitlines()[0]

        r = tmux("display", "-p", "-t", pane_id,
                  "#{session_attached}|#{pane_active}|#{window_active}")
        sess_att, pane_act, win_act = r.stdout.strip().split("|")
        print(f"  session_attached={sess_att}  pane_active={pane_act}  window_active={win_act}")
        bg = sess_att == "1" and pane_act == "1" and win_act == "0"
        if bg:
            ok("probe pane is in the background — the readings below mean what they say")
        else:
            bad("probe pane is NOT in the background — the readings below are meaningless, "
                "not just wrong (see the run instructions for attaching a client on a scratch socket)")

        env = tmux_env_for_pane(pane_id)
        payload = json.dumps({"hook_event_name": event, "message": message,
                               "cwd": f"/debug-chain-probe-{agent}"})
        r = subprocess.run(["zsh", str(REAL_NOTIFY), agent],
                            input=payload, capture_output=True, text=True, env=env)
        if r.returncode != 0:
            bad(f"agent-notify.sh exited {r.returncode}: {r.stderr.strip()}")

        r = tmux("display", "-p", "-t", pane_id,
                  "#{@agent_state}|#{@notice_txt}|#{@notice_name}|#{@notice_glyph}|#{@notice_at}")
        state, ntxt, nname, nglyph, nat = r.stdout.rstrip("\n").split("|", 4)
        print(f"  @agent_state={state!r}  @notice_txt={ntxt!r}  @notice_name={nname!r}  "
              f"@notice_glyph={nglyph!r}  @notice_at={nat!r}")
        ok(f"@agent_state={state}") if state == expect_state else \
            bad(f"@agent_state={state!r}, expected {expect_state!r}")

        if ntxt and not nat:
            bad("@notice_txt is set and @notice_at is empty — the \\; chain in agent-notify.sh "
                "died partway through (it sets txt first and at last), so something between "
                "those two `tmux set` calls is erroring")
            notice_set = False
        elif ntxt and nat:
            notice_set = True
            ok(f"notice set: {ntxt!r}") if expect_notice else \
                bad("a notice WAS set, and this event was not supposed to raise one for this agent — "
                    "the suppression in agent-notify.sh's case block is not firing")
        else:
            notice_set = False
            if expect_notice:
                bad("no notice was set — check the foreground test above; if it says background, "
                    "the fault is between the case-block glyph and the `if [[ $fg == 0 ]]` block")
            else:
                ok(f"no notice set{why_no_notice}")

        before = snapshot_options()
        r = subprocess.run(["zsh", str(REAL_STATUS_TICK)], capture_output=True, text=True,
                            env=tmux_env_for_pane(pane_id))
        restored = restore_options(before, skip=pane_id)
        if restored:
            warn(f"status-tick.sh swept {restored} option(s) on other panes; put back. "
                 "That is the sweep doing its job — on a machine where it is NOT running, "
                 "those notices are the evidence, which is why they are restored")
        print(f"  status-tick.sh stdout: {r.stdout!r}")
        if r.stderr.strip():
            print(f"  status-tick.sh stderr: {r.stderr.strip()}")
        tick_empty = not r.stdout.strip()
        if notice_set and tick_empty:
            bad("status-tick.sh printed nothing even though a notice was set — "
                "the notifier set the options and the sweep did not render them")
        elif notice_set:
            ok("status-tick.sh renders it")
        elif not tick_empty:
            bad("status-tick.sh printed something even though no notice was set")
    except ProbeFailed as e:
        bad(str(e))
    finally:
        if window_id:
            tmux("kill-window", "-t", window_id)
        elif borrowed and borrowed[1] is not None:
            restore_options({borrowed[0]: borrowed[1]}, skip=None)


def cmd_chain(args) -> int:
    say(f"chain — probing as agent={args.agent}" + (f" on socket {SOCKET}" if SOCKET else ""))

    # 1. symlinks resolve into this checkout
    for link, real in ((NOTIFY_LINK, REAL_NOTIFY), (STATUS_TICK_LINK, REAL_STATUS_TICK)):
        if not link.is_symlink():
            bad(f"{link} is not a symlink — run ./check.py links repo")
            continue
        try:
            resolved = link.resolve()
        except OSError:
            bad(f"{link} is a broken symlink")
            continue
        if resolved == real.resolve():
            ok(f"{link} -> checkout")
        else:
            warn(f"{link} -> {resolved}, not the checkout's {real} — "
                 "expected if `tap on` is running; ./debug.py tap status says")

    # 2. zsh -n against this machine's zsh
    zv = subprocess.run(["zsh", "--version"], capture_output=True, text=True)
    ok(f"zsh: {zv.stdout.strip() or zv.stderr.strip()}")
    for script in (REAL_NOTIFY, REAL_STATUS_TICK):
        r = subprocess.run(["zsh", "-n", str(script)], capture_output=True, text=True)
        ok(f"{script.name}: parses") if r.returncode == 0 else \
            bad(f"{script.name}: {r.stderr.strip()}")

    # 3. jq, tmux
    ok("jq present") if shutil.which("jq") else bad("jq missing — every event handler shells out to it")
    if not shutil.which("tmux"):
        bad("tmux missing — nothing past this line can run")
        return 1
    tv = tmux("-V")
    ok(f"tmux: {tv.stdout.strip()}") if tv.returncode == 0 else bad(f"tmux -V failed: {tv.stderr.strip()}")

    # 4. .tmux.conf actually sourced into the running server
    r = tmux("show", "-gv", "@agent_is")
    if r.returncode != 0 or not r.stdout.strip():
        bad("@agent_is is unset — .tmux.conf was never sourced into this server "
            "(a pull changes the file, not the running server; `tmux source-file ~/.tmux.conf`)")
        return 1
    ok(f"@agent_is set ({len(r.stdout.strip())} chars) — .tmux.conf is loaded")

    # 5. throwaway window, and whether it is genuinely in the background —
    # everything from here on is meaningless if this is wrong, so it is
    # checked and reported before anything that depends on it. With --target
    # there is no window to create and no session to guess: the caller named
    # the pane, and picking a session for it could only contradict them.
    session = None
    if not args.target:
        session, caveat = pick_session()
        if session is None:
            bad(f"no session to probe: {caveat}")
            return 1
        if caveat:
            warn(caveat)

    # 6/7. Two probes, not one. PermissionRequest first: every agent sets
    # state=wait and raises a ◆ notice for it with no branch on $agent, so it
    # exercises the notice link and the sweep regardless of --agent — this is
    # the probe that must catch "the notifier set the options and the sweep
    # printed nothing", which was the actual reported fault and which a
    # claude-only Notification probe cannot see, because agent-notify.sh
    # suppresses Notification's own glyph for claude and an empty sweep
    # reading is then indistinguishable from a healthy one.
    #
    # Notification second, as --agent: the one event whose glyph depends on
    # the agent (claude gets none, codex/opencode get one), so it is what
    # actually exercises the --agent flag — worth keeping, just not as the
    # only reading the default run depends on.
    run_probe(session, "PermissionRequest", "debug.py chain probe",
              args.agent, "wait", expect_notice=True, target=args.target)
    run_probe(session, "Notification", "debug.py chain probe",
              args.agent, "ready", expect_notice=(args.agent != "claude"),
              why_no_notice=" (expected: agent-notify.sh suppresses claude's own soft-ready glyph)",
              target=args.target)

    # 8. #() jobs actually run on status-right at all. #{E:status-right}
    # cannot answer this — it returns the format with job output missing,
    # which reads exactly like an empty bar. A marker file is the only way.
    say("status-right #() jobs")
    LOGDIR.mkdir(parents=True, exist_ok=True)
    marker = LOGDIR / f"chain-marker-{os.getpid()}"
    old_sr = tmux("show", "-gv", "status-right").stdout.rstrip("\n")
    try:
        # Inside the try, not before it, for the reason in run_probe: the finally
        # restores status-right to old_sr, and doing that when the set never
        # happened costs one tmux call and closes the interrupt window.
        tmux("set", "-g", "status-right", old_sr + f"#(touch {shlex.quote(str(marker))})")
        r = tmux("show", "-gv", "status-interval")
        try:
            interval = int(r.stdout.strip())
        except ValueError:
            interval = 15
        deadline = time.time() + interval * 2 + 3
        while time.time() < deadline and not marker.exists():
            time.sleep(0.3)
        if marker.exists():
            ok(f"marker appeared — #() jobs are running (status-interval={interval}s)")
        else:
            bad(f"marker never appeared within {interval * 2 + 3}s — #() jobs are not running "
                "(commonly: no client attached to redraw the bar)")
    finally:
        tmux("set", "-g", "status-right", old_sr)
        marker.unlink(missing_ok=True)

    print()
    if _fail:
        print(f"{RED}✘ {_fail} problem(s) above{OFF}")
    else:
        print(f"{GREEN}✔ the whole chain is alive{OFF}")
    return 1 if _fail else 0


# ── inspect ──────────────────────────────────────────────────

# status-tick.sh's own thresholds, read out of it rather than copied here: two
# files that have to agree about a number are two files that drift.
def tick_constant(name: str, default: int) -> int:
    try:
        for line in REAL_STATUS_TICK.read_text().splitlines():
            m = re.match(rf"\s*{name}=(\d+)", line)
            if m:
                return int(m.group(1))
    except OSError:
        pass
    return default


INSPECT_FIELDS = ("pane_id", "session_name", "window_index", "pane_index",
                  "pane_current_command", "pane_title", "window_active",
                  "pane_active", "session_attached", "@agent_state",
                  "@notice_txt", "@notice_name", "@notice_glyph", "@notice_at",
                  "@agent_screen_at", "E:@agent_lbl")


def read_panes(target=None) -> list:
    """Every field the tab is built from, for one target or for every pane.

    #{E:@agent_lbl} is the whole point of reading it here: it is the text the
    window tab actually shows, expanded by tmux from the same option the status
    line uses, so the report never has to reimplement .tmux.conf's conditionals
    and then disagree with them."""
    args = ["list-panes", "-F", panes_format(*INSPECT_FIELDS)] + \
           (["-t", target] if target else ["-a"])
    r = tmux(*args)
    if r.returncode != 0:
        raise ProbeFailed(f"{target or 'every pane'}: {r.stderr.strip() or 'tmux list-panes failed'}")
    return [dict(zip(INSPECT_FIELDS, row))
            for row in panes_rows(r.stdout, len(INSPECT_FIELDS))]


def diagnose(pane: dict, now: int, hold: int, freeze: int) -> list:
    """What is stuck, and what would unstick it. One entry per finding, and no
    entry at all for a pane that is behaving — a report that says something
    about every pane is one nobody reads to the end of."""
    out = []
    state, title = pane["@agent_state"], pane["pane_title"]
    label, nat, pid = pane["E:@agent_lbl"], pane["@notice_at"], pane["pane_id"]

    if label.startswith("Action Required"):
        if state == "wait":
            out.append(
                "the tab says Action Required because @agent_state is wait. Nothing retires a "
                f"wait on a timer — status-tick.sh retires a frozen `working` after FREEZE={freeze}s "
                "and nothing else. It clears when this pane's agent next fires UserPromptSubmit "
                "(you submit a prompt) or Stop (a turn ends). If the agent has exited, no hook "
                f"will fire again: `tmux set -pu -t {pid} @agent_state` is what is left.")
        elif re.match(r"^[^|]*Action Required \|", title):
            out.append(
                f"the tab says Action Required because the pane TITLE does, and @agent_state is "
                f"{state!r}. Codex writes its run state into its own title, so punto is relaying "
                "it and keeps relaying it until the agent rewrites it. Nothing in this repo "
                "clears that, and nothing in this repo set it.")
        else:
            out.append("the tab says Action Required and neither @agent_state nor the pane title "
                       "explains it — read @agent_lbl in .tmux.conf")

    if pane["@notice_txt"] and not nat:
        out.append(
            "@notice_txt is set with @notice_at empty. status-tick.sh skips such a pane outright "
            "(`[[ -n $nat ]] || continue`), so this notice is invisible to the sweep in both "
            "directions: never rendered, never cleared. The `\\;` chain in agent-notify.sh died "
            "between the two set calls — txt is set first and at is set last.")
    elif nat.isdigit():
        age = now - int(nat)
        if age >= hold:
            out.append(
                f"the notice is {age}s old and still set, past HOLD={hold}s. The sweep is not "
                "clearing it: either no client is redrawing status-right, or status-tick.sh is "
                "failing. `./debug.py chain` separates those two.")

    if state == "working" and pane["@agent_screen_at"].isdigit():
        age = now - int(pane["@agent_screen_at"])
        if age >= freeze:
            out.append(f"state is working and the screen last changed {age}s ago, past "
                       f"FREEZE={freeze}s — the sweep should have retired it and has not.")
    return out


def cmd_inspect(args) -> int:
    """Read-only. Nothing here sets, unsets or sweeps anything, so it can be
    pointed at a pane that is misbehaving right now without destroying the
    evidence — which running status-tick.sh by hand would do."""
    now = int(time.time())
    hold, freeze = tick_constant("HOLD", 30), tick_constant("FREEZE", 30)
    try:
        panes = read_panes(args.target)
    except ProbeFailed as e:
        bad(str(e))
        return 1

    # With a target the caller named the pane, so every pane of it is printed
    # even when clean — "nothing is set here" is the answer to half the
    # questions this command gets asked. Without one, only panes carrying
    # something, or the tab would be a list of every shell you have open.
    interesting = [p for p in panes
                   if args.target or p["@agent_state"] or p["@notice_at"] or p["@notice_txt"]
                   or p["E:@agent_lbl"].startswith(("Ready |", "Working |", "Action Required |"))]
    say(f"inspect — {len(interesting)} of {len(panes)} pane(s)"
        + (f" under {args.target}" if args.target else " carrying agent state")
        + (f" on socket {SOCKET}" if SOCKET else ""))
    if not interesting:
        print("  nothing set on any pane: no agent has reported into this server since it started.")
        return 0

    findings = 0
    for pane in interesting:
        fg = (pane["session_attached"] != "0" and pane["pane_active"] == "1"
              and pane["window_active"] == "1")
        print(f"\n{BOLD}{pane['session_name']}:{pane['window_index']}.{pane['pane_index']}{OFF}"
              f"  {pane['pane_id']}  {pane['pane_current_command']}"
              f"  {'foreground' if fg else 'background'}")
        print(f"  tab shows    : {pane['E:@agent_lbl']!r}")
        print(f"  @agent_state : {pane['@agent_state']!r}")
        nat = pane["@notice_at"]
        age = f"{now - int(nat)}s ago" if nat.isdigit() else f"{nat!r}"
        print(f"  notice       : glyph={pane['@notice_glyph']!r} name={pane['@notice_name']!r} "
              f"at={age}")
        print(f"                 txt={pane['@notice_txt']!r}")
        print(f"  pane_title   : {pane['pane_title']!r}")
        for line in diagnose(pane, now, hold, freeze):
            findings += 1
            warn(line)

    print()
    if findings:
        print(f"{YELLOW}{findings} thing(s) to explain above{OFF}")
    else:
        ok("every pane above is in a state something will clear")
    return 0


# ── watch / mark ─────────────────────────────────────────────


def cmd_watch(args) -> int:
    log_path = args.log or WATCH_LOG
    log_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"watching every pane's @agent_state / @notice_* every {args.interval}s -> {log_path}")
    print("Ctrl-C to stop. Never calls status-tick.sh: sweeping on its own schedule "
          "would clear the very notices this is trying to catch failing to clear.")
    try:
        with log_path.open("a") as f:
            while True:
                ts = int(time.time())
                r = tmux("list-panes", "-a", "-F",
                         panes_format("pane_id", "@agent_state", "@notice_txt",
                                      "@notice_name", "@notice_glyph", "@notice_at"))
                if r.returncode == 0:
                    try:
                        rows = panes_rows(r.stdout, 6)
                    except ProbeFailed as e:
                        # A sampler that dies on one bad tick loses the hours of
                        # recording it was left running for.
                        f.write(f"{ts}\tUNPARSED\t{e}\n")
                        f.flush()
                        time.sleep(args.interval)
                        continue
                    for pane_id, state, ntxt, nname, nglyph, nat in rows:
                        # Only panes with something set: a full sweep every tick
                        # for every idle pane would drown the one line that matters.
                        # ntxt is in the test and not redundant — @notice_txt set
                        # while @notice_at is empty is the exact fault run_probe
                        # names, from the `\;` chain in agent-notify.sh dying
                        # between the two, and testing state and nat alone drops
                        # precisely the pane worth catching.
                        if state or nat or ntxt:
                            # Newlines escaped for the tap wrapper's reason: one
                            # event is one line, or grepping the log at the
                            # moment it matters is worth nothing.
                            ntxt = ntxt.replace("\n", "\\n")
                            f.write(f"{ts}\tSAMPLE\t{pane_id}\tstate={state}\tnotice_at={nat}\t"
                                    f"notice_txt={ntxt}\tnotice_name={nname}\tnotice_glyph={nglyph}\n")
                    f.flush()
                time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nstopped.")
        return 0


def cmd_mark(args) -> int:
    log_path = args.log or WATCH_LOG
    log_path.parent.mkdir(parents=True, exist_ok=True)
    text = " ".join(args.text)
    ts = int(time.time())
    with log_path.open("a") as f:
        f.write(f"{ts}\tMARK\t{text}\n")
    print(f"marked {log_path} at {ts}" + (f": {text}" if text else ""))
    return 0


# ── tap ──────────────────────────────────────────────────────


def current_link_target():
    """None means missing or not a symlink. A dangling symlink instead comes
    back as its own (nonexistent) target — Path.resolve() doesn't raise for
    one — and every caller already rejects a target that isn't REAL_NOTIFY or
    WRAPPER_PATH, which a dangling link never is either."""
    if not NOTIFY_LINK.is_symlink():
        return None
    try:
        return NOTIFY_LINK.resolve()
    except OSError:
        return None


def write_wrapper():
    real = REAL_NOTIFY.resolve()
    lines = [
        "#!/bin/zsh",
        "# generated by debug.py tap on — do not edit by hand.",
        "# ~/.tmux/agent-notify.sh symlinks here while the tap runs;",
        f"# `./debug.py tap off` points it back at {real}.",
        "emulate -L zsh",
        "agent=${1:-claude}",
        "payload=$(cat)",
        "ts=$(date +%s)",
        "pane=${TMUX_PANE:-}",
        "# One line per event, newline escaped: Claude's .message carries the",
        "# text of your prompt, and a pretty-printed payload already arrives",
        "# split across lines — a log read by eye or by grep at the moment it",
        "# matters is worth nothing if one record spans several lines.",
        r"esc=${payload//$'\n'/\\n}",
        'print -r -- "$ts\t$agent\t$pane\t$esc" >> ' + shlex.quote(str(TAP_LOG)),
        'print -r -- "$payload" | exec ' + shlex.quote(str(real)) + ' "$agent"',
        "",
    ]
    WRAPPER_PATH.write_text("\n".join(lines))
    WRAPPER_PATH.chmod(0o755)


def cmd_tap(args) -> int:
    LOGDIR.mkdir(parents=True, exist_ok=True)

    if args.action == "status":
        target = current_link_target()
        if target is None:
            bad(f"{NOTIFY_LINK} is not a symlink, or is broken — outside what tap manages; run ./check.py links repo")
            return 1
        if target == REAL_NOTIFY.resolve():
            print("tap off")
        elif target == WRAPPER_PATH.resolve():
            print(f"tap ON — logging to {TAP_LOG}")
        else:
            warn(f"{NOTIFY_LINK} points at {target}, which is neither the checkout nor the tap wrapper")
        return 0

    if args.action == "on":
        target = current_link_target()
        if target == WRAPPER_PATH.resolve():
            print("tap already on")
            return 0
        if target != REAL_NOTIFY.resolve():
            bad(f"{NOTIFY_LINK} does not currently point into the checkout ({target}) — "
                "refusing to tap over an already-broken link; run ./check.py links repo first")
            return 1
        print("tap on will start recording every event this script receives, including "
              "Claude's .message field — which carries the text of your prompt — to "
              f"{TAP_LOG}.")
        write_wrapper()
        NOTIFY_LINK.unlink()
        NOTIFY_LINK.symlink_to(WRAPPER_PATH)
        print(f"tap on — {NOTIFY_LINK} -> {WRAPPER_PATH}")
        return 0

    # off
    target = current_link_target()
    if target == REAL_NOTIFY.resolve():
        print("tap already off")
        return 0
    NOTIFY_LINK.unlink(missing_ok=True)
    NOTIFY_LINK.symlink_to(REAL_NOTIFY)
    print(f"tap off — {NOTIFY_LINK} -> {REAL_NOTIFY}")
    return 0


# ── entry point ──────────────────────────────────────────────


def main() -> int:
    global SOCKET
    p = argparse.ArgumentParser(
        prog="debug.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--socket", metavar="NAME",
                    help="tmux -L NAME — talk to a non-default server instead of the one "
                         "three live agents use. Must come before the subcommand.")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_chain = sub.add_parser("chain", help="one-shot: is every link between a hook and the bar alive?")
    p_chain.add_argument("--agent", choices=("claude", "codex", "opencode"), default="claude")
    p_chain.add_argument("--target", metavar="WINDOW",
                         help="probe in a window you already have — anything tmux accepts as a "
                              "target: 3, sess:3, %%12. Its options are put back afterwards. Use it "
                              "when creating a window is what fails, or when you want the probe to "
                              "land somewhere you can watch.")

    p_inspect = sub.add_parser("inspect",
                               help="read-only: what state is each pane in, and what is stuck?")
    p_inspect.add_argument("target", nargs="?", metavar="WINDOW",
                           help="one window or pane (3, sess:3, %%12). Omit for every pane "
                                "carrying agent state.")

    p_watch = sub.add_parser("watch", help="continuous sampler, for faults that will not reproduce on demand")
    p_watch.add_argument("--interval", type=float, default=2.0, metavar="SECONDS")
    p_watch.add_argument("--log", type=Path, metavar="PATH")

    p_mark = sub.add_parser("mark", help="record, from a second pane, the moment you saw a bad notice")
    p_mark.add_argument("--log", type=Path, metavar="PATH")
    p_mark.add_argument("text", nargs="*")

    p_tap = sub.add_parser("tap", help="log every agent-notify.sh invocation with its full payload")
    p_tap.add_argument("action", choices=("on", "off", "status"))

    args = p.parse_args()
    SOCKET = args.socket

    if args.cmd == "chain":
        return cmd_chain(args)
    if args.cmd == "inspect":
        return cmd_inspect(args)
    if args.cmd == "watch":
        return cmd_watch(args)
    if args.cmd == "mark":
        return cmd_mark(args)
    return cmd_tap(args)


if __name__ == "__main__":
    sys.exit(main())
