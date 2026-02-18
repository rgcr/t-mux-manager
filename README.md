# ⚡ t - mux manager

**Lightweight tmux session and project manager written in Bash**

---

It creates sessions when they don’t exist and reuses them when they do — idempotent by default.

It can start sessions from simple `YAML` project files.

And if you hate writing `YAML`, it can generate the file for you from an existing session.

> Note: demo gif file was captured with `asciinema` so any visible render glitches were generated during the conversion process to `gif`

![tmux](https://github.com/user-attachments/assets/387ed811-1638-47cc-8a29-e3ff044f321d)


## Why?

Over the years I've used tools like [tmuxinator](https://github.com/tmuxinator/tmuxinator), [tmuxp](https://github.com/tmux-python/tmuxp) and recently [smug](https://github.com/ivaaaan/smug).

They are all great but in practice I keep going back to my own `t` function from my [dotfiles](https://github.com/rgcr/dotfiles/blob/daa9e1972ac4fd5a7142970056d34ecd0169b207/zsh/.functions.sh#L62) to manage my `tmux` sessions.

Eventually I realized:
  1. I didn’t need more features
  2. I needed something simpler.

So I built `t - mux manager`: a small standalone script that does exactly what I need, with no dependencies beyond `yq`


## Philosophy

`t - mux manager` is built around a few principles:

- Single command workflow
- Minimal dependencies
- Simple `YAML` structure
- Idempotent session and project handling
- Plain tmux commands. No unnecessary complexity. Just `tmux`

**And why just `t` as the command name?**

It's short, and easy to type when you're already in a terminal all day

## Requirements

- **tmux** >= 3.0
- **bash** >= 3.2
- [yq](https://github.com/mikefarah/yq)

Install `yq`:
```bash
# macOS
brew install yq

# Arch
sudo pacman -S yq
```

## Install

### Option 1 - Install with `brew`

`brew install rgcr/formulae/t-mux-manager`
<br><br>
### Option 2 - Clone the and symlink

Clone the repository and symlink the script into a directory in your `PATH`
(for example, `/usr/local/bin`):

```bash
git clone git@github.com:rgcr/t-mux-manager.git ~/.t-mux-manager
chmod +x ~/.t-mux-manager/t
ln -s ~/.t-mux-manager/t /usr/local/bin/t
```

Alternatively, if you prefer installing to `~/.local/bin`:

```bash
git clone git@github.com:rgcr/t-mux-manager.git ~/.t-mux-manager
chmod +x ~/.t-mux-manager/t
mkdir -p ~/.local/bin
ln -s ~/.t-mux-manager/t ~/.local/bin/t
```

### Option 3 — Download the script directly

Download the latest version and place it in a directory that is in your `PATH`
(for example, `~/.local/bin`):

```bash
curl -fsSL -o t https://raw.githubusercontent.com/rgcr/t-mux/main/t
chmod +x t
mkdir -p ~/.local/bin
mv t ~/.local/bin/
```

Make sure `~/.local/bin` is in your `PATH`:

`export PATH="$HOME/.local/bin:$PATH"`

## Shell completions

Tab completions for `zsh`, `bash`, and `fish` are available in the `completions/` directory.

### Zsh

Source directly in your `.zshrc`:

```zsh
source /path/to/t-mux-manager/completions/t.zsh
```

Or add to `fpath` (the `#compdef` header handles registration):

```zsh
fpath=(/path/to/t-mux-manager/completions $fpath)
autoload -Uz compinit && compinit
```

### Bash

Source in your `.bashrc`:

```bash
source /path/to/t-mux-manager/completions/t.bash
```

### Fish

Copy to your fish completions directory:

```fish
cp /path/to/t-mux-manager/completions/t.fish ~/.config/fish/completions/
```

## Usage

```bash
t                           # List active sessions and available projects
t myproject                 # Apply config, attach to session, or create new session
t -f <config.yml>           # Use an explicit project config file
t -e myproject              # Open project config in $EDITOR
t -s                        # Save current tmux session to a config file
t --reapply myproject        # Re-apply config and re-send commands
t -k myproject              # Kill the tmux session
t -d myproject              # Preview tmux commands (dry-run)
t -n myproject              # Create session without attaching
```

### Project resolution

When you run `t <name>`, it resolves in order:

1. If config file `~/.config/tmux-projects/<name>.yml` exists — apply it and attach
2. If tmux session named `<name>` already exists — attach to it
3. Neither — create a new bare session named `<name>` and attach

If the session already exists, `t` just attaches without reprocessing the config. Use `--reapply` to force re-apply.

### Config directory

Project configs live in `~/.config/tmux-projects/`. The directory is created automatically on first run.

### Saving sessions

Run `t -s` or `t --save-project` from inside a tmux session to save it as a project config. The current session's windows, pane layout, and working directories are captured. Commands cannot be saved (tmux doesn't store them).

Layout strings are only saved for multi-pane windows. If the config file already exists, it will ask for confirmation before overwriting.

### Flags


| Flag | Short | Description |
|------|-------|-------------|
| `--file <path>` | `-f` | Explicit project config file |
| `--edit` | `-e` | Open project config in `$EDITOR` |
| `--save-project` | `-s` | Save current tmux session to config file (must be inside a tmux session) |
| `--reapply` | | Re-apply config and re-send commands to existing session |
| `--dry-run` | `-d` | Print tmux commands instead of executing |
| `--no-attach` | `-n` | Create session but don't attach |
| `--kill` | `-k` | Kill the named tmux session |
| `--rm` | |             Delete project config file |
| `--sessions` | |             List only tmux sessions|
| `--projects` | |             List only available projects|
| `--verbose` | `-v` | Verbose/debug output |
| `--no-color` | | Disable colored output |
| `--help` | `-h` | Show help |
| `--version` | `-V` | Show version |


## Config format

Very minimal project config file, almost all my configs looks like this

```yaml
session: minimal
root: ~/workspace

windows:
  - name: w1
  - name: w2
  - name: w3
```


Another basic example:

```yaml
session: myproject        # required — tmux session name
root: ~/projects/myapp    # optional — default working directory

windows:
  - name: editor          # required — window name
    root: ./src            # optional — overrides session root
    commands:              # optional — sent to the first pane
      - vim .

  - name: services
    layout: even-horizontal  # optional — tmux layout (named or raw string)
    panes:                   # optional — if absent, single pane
      - commands:
          - npm run dev:frontend
        split: horizontal    # horizontal (default) or vertical
      - commands:
          - npm run dev:backend
        split: horizontal
        size: 40             # percentage of the split
```


**Don't you want to waste time writing YAML from scratch? Neither do I. Just run `t -s` from an existing tmux session to save it as a project config, then edit the file with `t -e <project>` to add commands and customize.**


### Pane fields


| Field | Default | Description |
|-------|---------|-------------|
| `commands` | — | List of commands to run in the pane |
| `split` | `horizontal` | Split direction: `horizontal` (panes side by side) or `vertical` (panes stacked top/bottom). Follows tmux convention where the name refers to the divider line direction |
| `size` | — | Pane size as a percentage |
| `root` | — | Working directory, overrides window/session root |


## Behaviour

By default `t` just attaches to an existing session. Project config is only applied when creating a new session or when `--reapply` is passed.

Windows created by `t` have `automatic-rename off` set, so tmux won't rename them when a command runs (e.g. `vim` won't rename the "editor" window to "vim").

Layout application is resilient — if a layout string doesn't match the pane count, `t` warns instead of crashing.

`t` is safe to run repeatedly:

1. **Session** — reuses if it exists, creates if not
2. **Windows** — reuses by name, creates missing ones
3. **Panes** — creates only the missing panes (splits)
4. **Commands** — sent only to newly created windows/panes. Use `--reapply` to re-send to existing ones

## Few examples

See the [`examples/`](examples/) directory:

- [`minimal.yml`](examples/minimal.yml) — very minimal example
- [`minimal-commands.yml`](examples/minimal-commands.yml) — two simple windows with commands
- [`fullstack.yml`](examples/fullstack.yml) — multiple windows with panes, layouts, and per-pane commands
- [`custom-layout.yml`](examples/custom-layout.yml) — named and raw tmux layout strings

## Tests (Only for development)

Tests use [bats-core](https://github.com/bats-core/bats-core):

```bash
# macos
brew install bats-core
# Arch
sudo pacman -S bats-core # or see bats-core docs for other platforms

# run all tests
bash tests/run.sh
```


## Contributing

We ❤️ contributions!

1. Fork the repo
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -m 'Add some feature'`
4. Push the branch: `git push origin my-new-feature`
5. Open a Pull Request 🚀
