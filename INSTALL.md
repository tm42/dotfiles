# Installing

Done by hand, by you or by an agent following this file. There is no installer, on
purpose: the install runs twice — once per machine — and after that `git pull` *is* the
update, because every file in `$HOME` is a symlink into this repo and is already live.
A program that runs twice and can delete your files is a bad trade.

Read each step before running it. Every command here is one you can inspect first.

Assumes macOS or Linux, Homebrew, and git. Steps 1–7 take about fifteen minutes.

---

## 1. Clone

```sh
git clone https://github.com/tm42/punto ~/punto
cd ~/punto
```

Anywhere works; `~/punto` is assumed below. The clone must stay where you put it —
the symlinks point at it, so moving it later breaks every one of them.

## 2. Install the tools

```sh
brew install tmux neovim fzf fzf-tab zsh-autosuggestions zsh-syntax-highlighting \
             zoxide bat jq ripgrep node tree-sitter-cli
brew install --cask font-jetbrains-mono-nerd-font
```

You also need a C compiler and `make`, which nvim shells out to. Both come with Xcode
Command Line Tools on macOS, which Homebrew already required, so a Mac that can run the
line above has them. On Linux, install `build-essential` (or your distribution's
equivalent). Check:

```sh
for t in cc make tree-sitter; do
  command -v "$t" >/dev/null && echo "ok   $t" || echo "FAIL $t"
done
```

Three of those are easy to skip and all three matter:

- **The font is not optional.** The prompt separators, the Claude statusline arrows, the
  git branch glyph and every nvim file icon are Private Use Area characters. Without a
  Nerd Font they render as empty boxes. **Then set your terminal to use it** — installing
  it is not enough.
- **`node`** is there because nvim's mason installs `pyright` and `typescript-language-server`
  from npm. Without it those two silently fail while the other two language servers work,
  which is more confusing than all four failing.
- **`tree-sitter-cli`, not `tree-sitter`.** The `tree-sitter` formula is the library, and
  brew installs it anyway as a neovim dependency — it ships no binary. `nvim-treesitter`
  shells out to the CLI to build each parser, so without this formula `python`, `bash`,
  `json`, `yaml` and `toml` fall back to vim's regex highlighting and nvim says so once
  per launch.

## 3. Clone the third-party pieces

Not vendored — other people's repos on their own release cadence.

```sh
git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
git clone --depth 1 https://github.com/MichaelAquilina/zsh-you-should-use.git \
    ~/.oh-my-zsh/custom/plugins/you-should-use
git clone --depth 1 https://github.com/fdellwing/zsh-bat.git \
    ~/.oh-my-zsh/custom/plugins/zsh-bat
git clone --depth 1 https://github.com/tmux-plugins/tpm.git ~/.tmux/plugins/tpm
```

**Check each one succeeded.** A failed clone can leave an empty directory behind, which
then looks installed forever after. Verify:

```sh
for d in ~/.oh-my-zsh ~/.oh-my-zsh/custom/plugins/you-should-use \
         ~/.oh-my-zsh/custom/plugins/zsh-bat ~/.tmux/plugins/tpm; do
  [ -d "$d/.git" ] && echo "ok   $d" || echo "FAIL $d"
done
```

lazy.nvim is deliberately absent — `init.lua` fetches it on first launch.

## 4. See what is in the way

This prints what the link step would touch. It changes nothing.

```sh
cd ~/punto
for pkg in dotfiles/*/; do
  (cd "$pkg" && find . -type f ! -name '.DS_Store' | sed 's|^\./||') | while read -r rel; do
    dst="$HOME/$rel"
    # A symlink in a PARENT directory is the dangerous case, and the one the
    # other three tests cannot see: [ -L ] resolves parent components, so a file
    # inside a symlinked directory reports as an ordinary FILE.
    via=""; p=$(dirname "$dst")
    while [ "$p" != "$HOME" ] && [ "$p" != "/" ]; do
      [ -L "$p" ] && via="$p -> $(readlink "$p")"
      p=$(dirname "$p")
    done
    if [ -n "$via" ];   then echo "PARENT $rel  (inside $via)"
    elif [ -L "$dst" ]; then echo "LINK  $rel -> $(readlink "$dst")"
    elif [ -e "$dst" ]; then echo "FILE  $rel"
    else                     echo "new   $rel"
    fi
  done
done
```

Read the output before continuing.

- `new` — nothing there, the link is free.
- `FILE` — a real file that step 5 will replace. Save anything you want to keep.
- `LINK` — already a symlink. Check where it points. **If it points into another repo,
  stop and look at that repo first.**
- `PARENT` — **stop.** A directory on the way to this file is a symlink into somewhere
  else, so step 5 would not write into `$HOME` at all: it would reach through the link and
  replace a real file in that other checkout. `ln -sfn`'s `-n` does not help here — it
  guards a symlink named as the target itself, never one in a parent component. Move or
  remove the parent symlink before continuing.

Move anything you want to keep:

```sh
mkdir -p ~/punto-backup
# for each FILE you care about:
mv ~/.zshrc ~/punto-backup/
```

## 5. Link

```sh
cd ~/punto
for pkg in dotfiles/*/; do
  (cd "$pkg" && find . -type f ! -name '.DS_Store' | sed 's|^\./||') | while read -r rel; do
    mkdir -p "$(dirname "$HOME/$rel")"
    ln -sfn "$PWD/$pkg$rel" "$HOME/$rel"
  done
done
```

What it does: for every file in every package, make the matching path in `$HOME` a
symlink pointing at the repo copy. `-f` replaces what is there — which is why step 4
comes first. `-n` stops it writing *inside* a directory symlink rather than replacing it.

Editing `~/.zshrc` now edits the repo file. That is the point: `git diff` shows your
change immediately and there is no copy-back step to forget.

## 6. Your machine's own values

```sh
mkdir -p ~/.config/punto
cp -n machine.zsh.example ~/.config/punto/machine.zsh   # -n: never clobber an edited one
$EDITOR ~/.config/punto/machine.zsh
```

**Set `TMUX_SESSIONIZER_ROOTS`** to where your projects actually live — the shipped value
is a guess and the project picker (`M-o`) is useless until it is right. The file is
gitignored and never committed; it and `~/.config/secrets/secrets.zsh` are where anything
machine-specific or secret belongs.

## 7. Point Claude Code at the statusline (skip if you do not use it)

Two keys in `~/.claude/settings.json`, and only two. Everything else in that file —
model, effort, permissions, plugin toggles, and `outputStyle` if another tool sets it — is left
alone.

```sh
# Claude Code does not write settings.json until you change a setting, so it may not
# exist yet. Seed it, then back it up — -n keeps the FIRST backup, so running this step
# twice cannot overwrite the pristine copy the undo in "Uninstalling" depends on.
[ -f ~/.claude/settings.json ] || echo '{}' > ~/.claude/settings.json
cp -n ~/.claude/settings.json ~/.claude/settings.json.bak

jq '
  def rewire($e): .hooks[$e] = (
      ((.hooks[$e] // [])
       | map(.hooks |= map(select((.command // "") | contains("claude-notify.sh") | not)))
       | map(select((.hooks | length) > 0)))
      + [{"matcher": "", "hooks": [{"type": "command",
          "command": "$HOME/.tmux/claude-notify.sh"}]}]);
  .statusLine = {"type": "command", "command": "~/.claude/statusline-agnoster.sh"}
  | rewire("Notification") | rewire("Stop")
' ~/.claude/settings.json.bak > ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json \
  || rm -f ~/.claude/settings.json.tmp

diff <(jq -S . ~/.claude/settings.json.bak) <(jq -S . ~/.claude/settings.json)
```

`rewire` strips any existing `claude-notify.sh` **hook** before adding the current one, so
running this twice does not give you two notifications per event.

It filters at the hook level, not the entry level, and that distinction is the whole
reason this is written out rather than done casually: one entry can hold several hooks. If
another tool's hook shares an entry with the notifier, dropping the entry takes that tool
out with it. `map(select((.hooks | length) > 0))` then removes an entry only once it is
genuinely empty.

The closing `diff` shows exactly what changed. Read it before moving on — it should name
`statusLine` and the two hook events and nothing else.

## 8. First run

In order. Each step needs the one before it.

```sh
exec zsh                 # 1. new shell, new config
```
```
tmux                     # 2. then press C-a I — TPM fetches its four plugins
```
```sh
nvim                     # 3. lazy.nvim fetches its plugins, then mason fetches the LSPs
```

`C-a` is the tmux prefix: hold Ctrl, tap `a`, release, then tap `I` (capital).

## 9. Check

```sh
./check.py
```

Read-only — it opens files and runs read-only commands, and has no code path that writes
anything.
Expect `✔ all good`. Anything else names the step to go back to.

Run one section on its own with `./check.py links`, or `tools`, `clones`, `machine`,
`claude`, `repo`.

---

## Updating

```sh
cd ~/punto && git pull
```

That is the whole update. The files in `$HOME` are symlinks into this repo, so a pull
changes them in place.

Two exceptions, both rare:

- **A new file appeared in a package.** Nothing links it yet — rerun steps 4 and 5.
  `./check.py links` says `missing` when this has happened.
- **`machine.zsh.example` gained a setting you want.** Copy the line across by hand;
  your `machine.zsh` is deliberately never overwritten.

## Uninstalling

```sh
cd ~/punto
for pkg in dotfiles/*/; do
  (cd "$pkg" && find . -type f ! -name '.DS_Store' | sed 's|^\./||') | while read -r rel; do
    [ -L "$HOME/$rel" ] && rm "$HOME/$rel"
  done
done
```

Only removes symlinks — `[ -L ]` means a real file you created later is left alone.
Then restore whatever you saved in step 4, and undo step 7 from
`~/.claude/settings.json.bak`.
