#!/usr/bin/env python3
"""check — is this machine set up the way INSTALL.md describes?

READ-ONLY. This script opens files and runs read-only commands — `which`, `brew
list`, `git ls-files`, `gitleaks detect`. It creates nothing, writes
nothing, and deletes nothing — there is no code path here that modifies the
filesystem, which is the whole reason it is a program and the installing is not.

Installing is done by hand, following INSTALL.md. Checking that every symlink
actually resolves into this repo is the one part that is tedious enough to
automate and cannot hurt you if it is wrong.

Stdlib only, Python 3.9 — what macOS ships at /usr/bin/python3.

    ./check.py            check everything
    ./check.py links      just one section (links, tools, clones, machine, claude, repo)
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent
PKGROOT = REPO / "dotfiles"
HOME = Path.home()
MACHINE = HOME / ".config" / "punto" / "machine.zsh"
CLAUDE_SETTINGS = HOME / ".claude" / "settings.json"

# Homebrew formulae the configs need. Formula → the command it provides, or None
# when it ships a shell source with no binary (checked under share/ instead).
TOOLS = {
    "tmux": "tmux",
    "neovim": "nvim",
    "fzf": "fzf",
    "zoxide": "zoxide",
    "bat": "bat",
    "jq": "jq",
    "ripgrep": "rg",
    "node": "node",          # mason installs pyright and ts_ls from npm
    "tree-sitter-cli": "tree-sitter",   # the `tree-sitter` formula is the library
                                        # neovim depends on and ships no binary
    "fzf-tab": None,
    "zsh-autosuggestions": None,
    "zsh-syntax-highlighting": None,
}

# Casks. Without a Nerd Font every powerline separator, the git branch glyph and
# every nvim devicon renders as tofu — the prompt and statusline stop matching,
# which is the first visible thing this setup claims.
FONT_CASKS = ["font-jetbrains-mono-nerd-font"]

CLONES = {
    ".oh-my-zsh": HOME / ".oh-my-zsh",
    "you-should-use": HOME / ".oh-my-zsh/custom/plugins/you-should-use",
    "zsh-bat": HOME / ".oh-my-zsh/custom/plugins/zsh-bat",
    "tpm": HOME / ".tmux/plugins/tpm",
}
TPM_PLUGINS = ["tmux-sensible", "tmux-yank", "tmux-thumbs", "extrakto"]

STATUSLINE_CMD = "~/.claude/statusline-agnoster.sh"
NOTIFY_NAME = "claude-notify.sh"
NOTIFY_EVENTS = ("Notification", "Stop")

BOLD, DIM, GREEN, YELLOW, RED, OFF = (
    "\033[1m", "\033[2m", "\033[32m", "\033[33m", "\033[31m", "\033[0m")
if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
    BOLD = DIM = GREEN = YELLOW = RED = OFF = ""

_fail = 0


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


def tilde(p) -> str:
    s = str(p)
    return "~" + s[len(str(HOME)):] if s.startswith(str(HOME)) else s


def brew_prefix():
    for p in ("/opt/homebrew", "/usr/local", "/home/linuxbrew/.linuxbrew"):
        if Path(p, "bin", "brew").is_file():
            return Path(p)
    return None


def packages():
    return sorted(p.name for p in PKGROOT.iterdir() if p.is_dir())


def managed(pkg):
    """Files a package owns. Skips OS and editor droppings, which are not config
    and would otherwise be reported as unlinked forever."""
    root = PKGROOT / pkg
    skip = {".DS_Store", "Thumbs.db"}
    return sorted(p.relative_to(root) for p in root.rglob("*")
                  if p.is_file() and p.name not in skip
                  and not p.name.endswith(("~", ".swp", ".swo", ".orig", ".rej")))


# ── Sections ─────────────────────────────────────────────────


def check_links():
    say("links")
    for pkg in packages():
        counts = {}
        examples = {}
        for rel in managed(pkg):
            src, dst = PKGROOT / pkg / rel, HOME / rel
            if dst.is_symlink():
                try:
                    resolved = dst.resolve()
                except OSError:
                    st = "broken link"
                else:
                    if resolved == src.resolve():
                        st = "linked"
                    elif REPO in resolved.parents:
                        st = "linked to the wrong file in this repo"
                    else:
                        st = "links outside this repo"
            elif not dst.exists():
                st = "missing"
            else:
                # A real file where a link should be. Two very different causes:
                # never installed, or a program replaced the link by writing a
                # new file over it — which silently detaches it from the repo.
                same = False
                try:
                    same = src.read_bytes() == dst.read_bytes()
                except OSError:
                    pass
                st = "real file, same content" if same else "real file, DIFFERENT content"
            counts[st] = counts.get(st, 0) + 1
            examples.setdefault(st, str(rel))

        if set(counts) == {"linked"}:
            ok(f"{pkg}: {counts['linked']} linked")
        else:
            detail = ", ".join(f"{v} {k}" for k, v in sorted(counts.items()))
            bad(f"{pkg}: {detail}")
            for st, first in sorted(examples.items()):
                if st != "linked":
                    print(f"      e.g. {first}  — {st}")


def check_tools():
    say("tools")
    prefix = brew_prefix()
    if not prefix:
        warn("no Homebrew found — the three zsh plugins in .zshrc §7 cannot load")
    for formula, command in TOOLS.items():
        if command:
            ok(command) if shutil.which(command) else bad(f"{command} missing  (brew install {formula})")
        elif prefix and (prefix / "share" / formula).is_dir():
            ok(formula)
        else:
            bad(f"{formula} missing  (brew install {formula})")

    # Casks are not on PATH, so ask brew. If brew cannot answer, fall back to
    # looking for the files, and say which check was used rather than guessing.
    installed = ""
    if prefix:
        installed = subprocess.run([str(prefix / "bin" / "brew"), "list", "--cask"],
                                   capture_output=True, text=True).stdout
    for cask in FONT_CASKS:
        if cask in installed:
            ok(cask)
        elif list(Path(HOME / "Library" / "Fonts").glob("*Nerd*")) if (HOME / "Library" / "Fonts").is_dir() else False:
            warn(f"{cask} not installed, but a Nerd Font is present in ~/Library/Fonts")
        else:
            bad(f"{cask} missing  (brew install --cask {cask})"
                " — powerline separators and nvim icons will render as tofu")


def check_clones():
    say("third-party clones")
    for name, path in CLONES.items():
        # A .git directory, not just any directory: a failed clone can leave an
        # empty tree behind, and a bare is_dir() would call that success forever.
        if (path / ".git").is_dir():
            ok(name)
        elif path.is_dir():
            bad(f"{name}: {tilde(path)} exists but is not a git clone — delete it and clone again")
        else:
            bad(f"{name} missing — see INSTALL.md step 3")
    for p in TPM_PLUGINS:
        path = HOME / ".tmux" / "plugins" / p
        ok(p) if path.is_dir() else warn(f"{p} missing — press C-a I inside tmux")
    lazy = HOME / ".local/share/nvim/lazy/lazy.nvim"
    ok("lazy.nvim") if lazy.is_dir() else warn("lazy.nvim missing — launch nvim once")


def check_machine():
    say("machine-specific")
    if not MACHINE.is_file():
        bad(f"{tilde(MACHINE)} absent — .zshrc §2 sources it; the project picker has no roots")
        return
    roots = []
    for line in MACHINE.read_text().splitlines():
        line = line.strip()
        if line.startswith("export TMUX_SESSIONIZER_ROOTS="):
            value = line.split("=", 1)[1].strip().strip('"').strip("'")
            roots = [os.path.expandvars(os.path.expanduser(r))
                     for r in value.split(":") if r]
    if not roots:
        warn("machine.zsh sets no TMUX_SESSIONIZER_ROOTS — M-o falls back to"
             " ~/projects ~/code ~/dev ~/src ~/work ~/repos")
        return
    # Check the directories, not the line. The shipped example already contains
    # the line, so testing for its presence passes on exactly the unedited state
    # this check exists to catch.
    live = [r for r in roots if Path(r).is_dir()]
    if live:
        ok(f"machine.zsh: {len(live)}/{len(roots)} roots exist ({', '.join(tilde(Path(r)) for r in live)})")
    else:
        bad(f"machine.zsh names roots that do not exist: {', '.join(roots)}"
            " — still the shipped example?")

    secrets = HOME / ".config/secrets/secrets.zsh"
    ok("secrets.zsh present") if secrets.is_file() else \
        warn("secrets.zsh absent (fine if this machine needs no API keys)")


def check_claude():
    say("Claude Code")
    if not CLAUDE_SETTINGS.is_file():
        warn(f"{tilde(CLAUDE_SETTINGS)} absent — see INSTALL.md step 7")
        return
    try:
        s = json.loads(CLAUDE_SETTINGS.read_text())
    except json.JSONDecodeError as exc:
        bad(f"settings.json does not parse: {exc}")
        return
    if not isinstance(s, dict):
        bad("settings.json is not a JSON object")
        return

    if (s.get("statusLine") or {}).get("command") == STATUSLINE_CMD:
        ok("statusLine points at this repo's script")
    else:
        bad(f"statusLine is {(s.get('statusLine') or {}).get('command')!r}"
            f" — expected {STATUSLINE_CMD!r}")

    absent = [e for e in NOTIFY_EVENTS
              if not any(NOTIFY_NAME in str(h.get("command", ""))
                         for entry in s.get("hooks", {}).get(e, []) or []
                         for h in entry.get("hooks", []) or [])]
    ok("notifier wired on " + ", ".join(NOTIFY_EVENTS)) if not absent else \
        bad("notifier missing on " + ", ".join(absent))


def check_repo():
    say("repo hygiene")
    r = subprocess.run(["git", "-C", str(REPO), "ls-files"],
                       capture_output=True, text=True)
    if r.returncode:
        warn("not a git repo — skipping")
        return
    names = {"secrets.zsh", ".netrc", ".pypirc", "hosts.yml", "credentials",
             "rclone.conf", "settings.local.json", ".claude.json"}
    leaked = [t for t in r.stdout.split() if Path(t).name in names]
    bad("tracked credential file(s): " + " ".join(leaked)) if leaked else \
        ok("no known credential file is tracked")

    if shutil.which("gitleaks"):
        g = subprocess.run(["gitleaks", "detect", "--source", str(REPO),
                            "--no-banner", "--redact"], capture_output=True)
        ok("gitleaks: clean") if g.returncode == 0 else \
            bad("gitleaks found something — run: gitleaks detect --source . --redact")
    else:
        warn("gitleaks not installed — the pre-commit hook fetches it on demand")


SECTIONS = {
    "links": check_links,
    "tools": check_tools,
    "clones": check_clones,
    "machine": check_machine,
    "claude": check_claude,
    "repo": check_repo,
}


def main() -> int:
    wanted = sys.argv[1:] or list(SECTIONS)
    for name in wanted:
        if name in ("-h", "--help"):
            print(__doc__)
            return 0
        if name not in SECTIONS:
            print(f"no such section: {name}\navailable: {', '.join(SECTIONS)}",
                  file=sys.stderr)
            return 2
    for name in wanted:
        SECTIONS[name]()
    print()
    if _fail:
        print(f"{RED}✘ {_fail} problem(s){OFF} — see INSTALL.md")
    else:
        print(f"{GREEN}✔ all good{OFF}")
    return 1 if _fail else 0


if __name__ == "__main__":
    sys.exit(main())
