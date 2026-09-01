# punto

zsh, tmux and Neovim, set up to behave as one environment rather than three programs that
happen to share a terminal. Machine-specific paths and every credential stay out of the repo.

macOS and Linux. MIT.

A personal setup, published so I can reproduce it on a new machine — not a framework and not
a distribution. Ideas and corrections are welcome. It changes when my setup changes, with no
notice and no migration path, so fork it rather than track it.

Installing is done by hand, following [INSTALL.md](INSTALL.md) — about fifteen minutes, once
per machine. There is no installer on purpose: after the first install `git pull` *is* the
update, because every file in `$HOME` is a symlink into this repo and is already live.

```bash
git clone https://github.com/tm42/punto ~/punto
cd ~/punto
$EDITOR INSTALL.md      # read it, then follow it
./check.py              # read-only: did it work?
```

---

## check.py

The only program here, and it is **read-only** — it opens files and runs a handful of
read-only commands, and has no
code path that writes, creates or deletes anything. That is why it exists and the installing
does not: checking that every symlink actually resolves into this repo is tedious by hand and
cannot hurt you if it is wrong.

```bash
./check.py               # everything
./check.py links tools   # one or more sections
```

Sections: `links`, `tools`, `clones`, `machine`, `claude`, `repo`. It checks that every
managed path is a symlink into this repo (naming anything that is a real file, a broken link,
or a link somewhere else), that the Homebrew formulae and the Nerd Font cask are installed,
that each third-party clone is a real clone rather than an empty directory left by a failed
one, that `machine.zsh` names project roots **that exist**, that Claude Code points at the
statusline and the notifier, and that no credential file is tracked.

---

## How the linking works

The real file lives in the repo; `$HOME` gets a signpost pointing at it.

```
~/.zshrc  ──▶  ~/punto/dotfiles/zsh/.zshrc
```

So editing `~/.zshrc` *is* editing the repo file — `git diff` shows it immediately, and there
is no "remember to copy it back" step to forget, and `git pull` updates your live config with
no install step at all. GNU Stow is the usual tool for this; INSTALL.md uses a plain `ln -s`
loop instead, so there is nothing to install before you can install.

Each package is a directory under `dotfiles/` whose contents mirror `$HOME`:

```
dotfiles/
  zsh/     .zshrc
  tmux/    .tmux.conf + .tmux/{pane-status.zsh,git-status.sh,sessionizer.sh,
                               cheat.sh,claude-notify.sh}
  nvim/    .config/nvim/{init.lua,lazy-lock.json,lua/**}
  claude/  .claude/statusline-agnoster.sh
  docs/    .nvimcheatsheet.md, .tmux-quickstart.md
  uv/      .config/uv/uv.toml
```

**The scope rule:** this repo is the terminal environment — zsh, tmux, nvim, and the tools
those three call. Nothing else. Other tools that install themselves are not in it and are
not touched by it, even where they write to the same files.

Claude Code appears in one place on screen, because in one place it renders into the
terminal: `statusline-agnoster.sh`, whose palette is matched to the agnoster prompt. INSTALL.md
step 7 writes two keys into `~/.claude/settings.json` — `statusLine`, and a `claude-notify.sh`
entry on the `Notification` and `Stop` hooks — and leaves every other key alone, including
hooks belonging to other tools that share an entry with it.

### Not vendored

oh-my-zsh and its two custom plugins, TPM and its four tmux plugins, lazy.nvim. Other
people's repos on their own cadence; INSTALL.md step 3 clones them. lazy.nvim is not even cloned —
`init.lua` fetches it on first launch. `lazy-lock.json` **is** tracked, so both machines
resolve the same plugin commits.

---

## What is actually integrated

Four seams, none of them obvious from the individual files.

### One movement grid across nvim splits and tmux panes

`M-h/j/k/l` moves left/down/up/right — through an nvim split boundary and out into the
neighbouring tmux pane without changing key. tmux decides which it is: `is_vim` in
`.tmux.conf` reads the pane's process table and forwards the key when nvim is running there,
consuming it otherwise.

The regex is written to work on BSD grep as well as GNU. Upstream ships `\S` and `[^ ]*`;
older BSD greps read `\S` as a literal `S`, and `[^ ]*/` refuses to backtrack to empty.
`(.*/)?` is the form that works on both, and on every version.

(The `\S` half no longer bites: BSD grep 2.6.0-FreeBSD, which current macOS ships, handles
it correctly. `(.*/)?` costs nothing, so it stays.)

`M-H/J/K/L` resizes by one cell, repeatable, and lives in `.tmux.conf` alone — nvim has no
say in resizing. The *movement* keys above are the ones both halves must agree on: they are
mapped in `.tmux.conf` and in `nvim/lua/plugins/tmux-navigator.lua`, and changing one
silently breaks the other.

### The window tab tells you what the pane is doing

`@tab` is four branches, first match wins, every one capped at exactly 40 display cells:

| Pane is | Tab shows | Example |
|---|---|---|
| nvim | `✎:` + repo/file | `✎:punto/README.md` |
| Claude Code | session name | `punto` |
| running a command | `▶` + command | `▶ pytest -x` |
| finished a command | `✔` or `✘<code>` + command | `✘1 cargo build` |
| idle | cwd basename | `~` |

The exit glyph survives the command, which is the point — a build that failed while you were
in another window still says so. Visiting the pane acknowledges it and the tab drops back to
the directory name; `▶` is never cleared that way, because a running command is not news you
have already read.

`~/.tmux/pane-status.zsh` hooks zsh's `preexec`/`precmd` and publishes `@ps_state`, `@ps_cmd`,
`@ps_code` and `@ps_dur` as tmux pane options; `.tmux.conf` renders them. The nvim branch
reads the terminal title, which `nvim/lua/options.lua` sets — and truncates there rather than
in tmux, because tmux's `#{=/-N/…:}` can only blind-cut a tail and that eats the repo name
whole. Both caps are 37 on purpose: at 37 tmux's backstop never fires, so you never get a
second `…`.

A command slower than 30s finishing in a **background** pane also raises a status-line nudge.
Foreground panes stay quiet — you just watched it finish. `TMUX_PS_NOTIFY_SEC=0` disables it.

### Prompt and Claude statusline are one bar

The agnoster segments — host, venv, path, git — and Claude Code's statusline use the same hex
values, so the prompt and the bar above it read as one unit. The zsh half is `.zshrc` §3; the
other half is `statusline-agnoster.sh`.

That script's second line is a load gauge: model, effort, context percent, then the 5-hour and
7-day rate-limit windows — the 5-hour with the time it resets, the 7-day with the weekday. Two details worth knowing:

- **Context bands escalate earlier on a 1M window** (10/20/40% instead of 20/40/60%), because
  effective attention degrades long before the tokens fill.
- **The green `1m` badge** tracks the effective window size, not the model string, so it does
  not flicker when Claude Code drops the `[1m]` suffix on its own.
- **A `1m✗` badge** means the model id still says `[1m]` while the served window is 200k — the
  long-context credit clamp. That one *is* keyed on the id, so it says what Claude Code claims
  rather than what it delivers.

Hex colours need a truecolor terminal, and under tmux Claude Code additionally needs
`CLAUDE_CODE_TMUX_TRUECOLOR=1` (`.zshrc` §3), or it clamps 24-bit to the 256 cube and the
palette collapses into itself.

### Claude Code tells you when it needs you

`~/.tmux/claude-notify.sh` fires on the `Notification` and `Stop` hooks and raises a tmux
message plus a macOS notification — but only when the Claude pane is in the background. It
always exits 0: a hook that errors nags Claude, not you.

---

## Keys worth knowing

Prefix is `C-a`. Alt bindings are prefix-less.

### tmux

| Key | Does |
|---|---|
| `M-o` | fzf project picker — attach-or-create one session per directory, open sessions first |
| `M-s` | floating scratch shell; same session every time, so it keeps its history. Same key closes it |
| `M-\` | copy mode |
| `M-[` / `M-]` | previous / next window |
| `M-0`…`M-9` | jump to window N |
| `C-a F` | fuzzy-search every tmux command with a live man-page preview |
| `C-a g` | thumbs — hint letters on every path/url/hash on screen; press one to copy |
| `C-a Tab` | extrakto — fuzzy-search every token on screen and in scrollback |
| `C-a \|` / `C-a -` | split vertical / horizontal, inheriting the current path |
| `C-a z` | zoom pane (the bar says `ZOOM`, which is why you stop losing panes) |
| `C-a r` | reload config |
| `C-a ?` | this config's quickstart, in a popup |

`M-o` was `M-f` until a terminal's opt+right turned out to send `M-f`, which zsh uses for
forward-word — tmux ate it before the shell saw it.

`C-a F` is worth a minute: every tmux command with a one-sentence description, searchable by
concept, and the preview decodes tmux's opaque single-letter flags. Typing `link` finds
`link-window`, `swap-window` and `move-window` — the whole family, because each one's sentence
names the others.

### Neovim

Leader is Space. Press it and wait — which-key lists everything. Full sheet at
`~/.nvimcheatsheet.md`, which `<leader>?` opens in a split. tmux has the matching pair:
`~/.tmux-quickstart.md` on `C-a ?`.

### zsh

`fzf-tab` replaces the completion menu with a fuzzy finder. Autosuggestions come from history;
`→` accepts. `zoxide` learns your directories: `z proj` jumps.

`.zshrc` §7's load order is mandatory and the file says so in place. Each plugin wraps the ZLE
widgets installed before it: fzf-tab needs `compinit` to have already run, and syntax
highlighting must be dead last or it never sees — and so never colours — what the others
installed.

---

## Secrets and per-machine values

Nothing here is a credential, and the split that keeps it that way is structural rather than
disciplinary. Three files are read at shell startup and none is committed:

| File | Holds | Seeded by |
|---|---|---|
| `~/.config/secrets/secrets.zsh` | API keys and tokens, mode 600 | you |
| `~/.config/punto/machine.zsh` | per-machine paths | you, from `machine.zsh.example` (INSTALL.md step 6) |
| `~/.zshrc.local` | anything else this one machine needs | you, if ever |

A token has no *reason* to live in a tracked file — that is the actual protection. `.gitignore`
is a backstop and a weak one: it cannot help with a secret pasted into a file that is already
tracked.

**The control that works is the pre-commit hook.** gitleaks scans the staged diff against ~150
credential patterns and fails the commit:

```bash
pre-commit install     # per clone — INSTALL.md step 8; git does not clone hooks
```

Commit time is the only cheap moment. Git history is permanent — a credential that lands in a
commit is burned regardless of what a later commit removes.

Two non-obvious habits:

- **`uv … --help` prints live secrets.** uv renders environment defaults as `[env: VAR=<value>]`,
  so any `UV_*` secret in your environment leaks to scrollback, CI logs, or a screen share.
  `uv/.config/uv/uv.toml` is one line — `keyring-provider = "subprocess"` — which is the fix:
  use the system keychain rather than an exported variable for a credential used monthly.
- **`~/.claude/shell-snapshots/` freezes your shell environment at session start**, tokens
  included. Gitignored here; leave it that way.

### The four things that differ per machine

1. **Homebrew prefix** — `.zshrc` §1 probes `/opt/homebrew`, `/usr/local` and
   `/home/linuxbrew/.linuxbrew`. `brew --prefix` cannot answer, because brew is not on `PATH`
   until that block puts it there.
2. **`$HOME`** — `.tmux.conf` uses `#{HOME}`; tmux resolves an unknown format name from the
   environment.
3. **Project roots** — `TMUX_SESSIONIZER_ROOTS` and `TMUX_SESSIONIZER_EXTRA`, colon-separated,
   in `machine.zsh`. Roots are scanned at depth 1 *and* 2, so both `$root/apps` and
   `$root/apps/thing` are offered.
4. **Anything else** — `machine.zsh`, or `~/.zshrc.local` which `.zshrc` §11 sources last.

Git config is deliberately absent: identity, signing and remotes differ enough between a
personal and a work machine that syncing them is a liability. Nothing here needs it — the
status-bar branch segment, `git-status.sh` and gitsigns all call git plumbing directly and
work with no configuration at all.
