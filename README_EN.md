# terminal-setup

A terminal environment bootstrap for new machines. It installs the required command-line tools, uses chezmoi to write configuration into Home, and keeps the environment aligned through package manifests.

The default starter is public, credential-free, and ready to use. macOS uses Homebrew; Linux/WSL prefer apt and use Pixi global for packages apt cannot provide; native Windows uses Pixi global. uv owns Python tools and fnm owns Node.js. GUI apps, casks, AI clients, and specialist tools are recommendations only.

**[中文文档](README.md) · [Security policy](SECURITY.md) · [Maintenance policy](CONTRIBUTING.md)**

## Choose Your Path

| Your situation | Start here |
|---|---|
| A fresh Mac using the generic public configuration | [Fresh Mac](#fresh-mac-from-zero) |
| You already own a chezmoi/dotfiles repository | [Restore a private environment](#restore-your-own-chezmoi-repository) |
| Debian, Ubuntu, WSL, or a Linux server | [Linux/WSL](#debian-ubuntu-wsl-or-a-linux-server) |
| Native Windows with PowerShell 7 | [Native Windows](#native-windows) |
| You only want to inspect the planned actions | [Preview first](#preview-before-installing) |

If chezmoi is new to you, complete the Mac, Linux/WSL, or native Windows path for your platform before returning to the design and maintenance sections.

## Fresh Mac: From Zero

This is the recommended beginner path. You do not need to preinstall Homebrew, chezmoi, Node.js, or each CLI separately.

### Step 1: Confirm Apple's command-line tools

Open the built-in Terminal app and run:

```sh
xcode-select --install
```

Wait for the macOS installer to finish before continuing. It provides Git, Clang, make, and the macOS SDK. `/usr/bin/gcc` invokes Apple's Clang-compatible driver, not GNU GCC.

A fresh Mac needs the bundled Git before it can clone this project, so installing the tools manually first is the recommended path. If you obtained the repository another way, you can run `./setup.sh` directly: the script checks Xcode Command Line Tools, opens the same macOS system installer when they are missing, and asks you to rerun it after installation finishes.

### Step 2: Download this project

This is the real repository URL and does not need to be replaced:

```sh
git clone https://github.com/CanoNandMacaroN/terminal-setup.git
cd terminal-setup
```

### Step 3: Preview, then install

Inspect the planned actions first:

```sh
./setup.sh --dry-run
```

Then start the real installation:

```sh
./setup.sh
```

The installer will:

1. Check Xcode Command Line Tools; when missing, open the macOS system installer and stop before later steps until installation finishes.
2. Run Homebrew's official installer when Homebrew is missing.
3. Install Git, chezmoi, and the generic CLI toolset.
4. Copy `starter/` into the local chezmoi source state.
5. Back up existing files that chezmoi is about to manage.
6. Apply the Zsh, Git, Starship, and related baseline configuration.
7. Reconcile the Brewfile and uv tool manifest.
8. Install Node LTS through fnm and enable pnpm through Corepack.
9. Verify the resulting state with `chezmoi verify`.

Homebrew may ask for confirmation or the system password. That is normal behavior from its official installer.

### Step 4: Enter and verify the new environment

```sh
exec zsh -l
cd terminal-setup
./doctor.sh
```

`Doctor passed` means required components and the chezmoi state are healthy. Missing optional tools appear as warnings and do not necessarily indicate a failed installation.

Your chezmoi source now lives at:

```text
~/.local/share/chezmoi
```

It is already a local Git repository, but it is not connected to your private remote yet. You can use it immediately and add your own private remote when you want cross-machine synchronization.

On Linux servers, the login environment in `.zprofile` exposes Node, pnpm, and CLIs installed through pnpm (such as Codex). This also makes them visible to desktop clients that inspect the host through a non-interactive SSH Zsh session; reconnect the SSH session after changing the profile.

### Optional one-line bootstrap

After Git is available, the bootstrap script can clone into a temporary directory and run the installer:

```sh
curl -fsSL https://raw.githubusercontent.com/CanoNandMacaroN/terminal-setup/main/bootstrap.sh \
  | sh -s -- https://github.com/CanoNandMacaroN/terminal-setup.git
```

This is convenient for users comfortable with piped scripts. Beginners should prefer the clone, dry-run, and install sequence above so the code and preview remain visible.

## Restore Your Own Chezmoi Repository

If you already have a private dotfiles repository, download this project first:

```sh
git clone https://github.com/CanoNandMacaroN/terminal-setup.git
cd terminal-setup
```

Set the following variable to your own repository. This value must come from you because a public project cannot know where your private source is hosted:

```sh
DOTFILES_REPO='git@github.com:your-account/your-dotfiles-repository.git'
./setup.sh --repo "$DOTFILES_REPO"
```

If the private source contains age ciphertext, also provide an exported identity file from your password manager:

```sh
DOTFILES_REPO='git@github.com:your-account/your-dotfiles-repository.git'
AGE_KEY_FILE="$HOME/Downloads/key.txt"

./setup.sh \
  --repo "$DOTFILES_REPO" \
  --age-key-file "$AGE_KEY_FILE"
```

Before running it, confirm that:

- `AGE_KEY_FILE` is an age identity, not an SSH private key.
- It contains a private-key line beginning with `AGE-SECRET-KEY-1`.
- If the password manager provides only that line, `setup.sh` normalizes it to the standard chezmoi identity format before installation.
- The identity is never stored inside the dotfiles repository.
- Each machine keeps its own SSH private keys instead of sharing one key through chezmoi.

The installer copies the identity to `~/.config/chezmoi/key.txt` with mode `600`. Chezmoi then decrypts encrypted source files automatically during apply.

If you only need chezmoi's shortest restore path, manually prepare chezmoi and the age identity, then run:

```sh
chezmoi init --apply git@github.com:your-account/your-dotfiles-repository.git
```

That command restores dotfiles only. `setup.sh --repo` additionally handles platform dependencies, package manifests, backups, Node/pnpm, and final verification.

### Restore an SSH private key and derive its public key

SSH private keys do not belong in chezmoi or Git. Restore them separately from a password manager, hardware token, or controlled offline backup. When you intentionally reuse the same private key on a new machine, derive its public key after restoring it:

```sh
install -d -m 700 ~/.ssh
install -m 600 /path/from/password-manager/id_ed25519 ~/.ssh/id_ed25519
ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub
chmod 644 ~/.ssh/id_ed25519.pub
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

`ssh-keygen -y` derives the matching public key; it does not create a new identity. After checking the fingerprint, load it with:

```sh
set-ssh-key id_ed25519
ssh-add -l
```

When the target machine should have its own identity, generate a new key there and register only its public key. Never add a private key to the public starter.

## Debian, Ubuntu, WSL, or a Linux Server

Install the three packages required to download the repository:

```sh
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
```

Then use the real project URL:

```sh
git clone https://github.com/CanoNandMacaroN/terminal-setup.git
cd terminal-setup
./server-setup.sh --dry-run
./server-setup.sh
```

Enter Zsh and run the health check:

```sh
exec zsh -l
cd terminal-setup
./doctor.sh
```

The server workflow first installs manifest packages available through apt, then installs Pixi under `~/.pixi` to fill the remaining CLI baseline. Later chezmoi applies inspect dpkg ownership and continue reusing apt-provided commands, invoking Pixi only for missing tools. The installer attempts to make Zsh the login shell by default.

If the account is not in sudoers, or an administrator has already installed the system dependencies, use user-only mode:

```sh
./server-setup.sh --user-only
```

User-only mode does not call `sudo`, run `apt`, or change the login shell. It only requires preinstalled `curl` and `git`. Later applies use the same apt-first policy: commands already provided by dpkg are reused, while Pixi fills missing CLIs under Home. Zsh autosuggestions and syntax-highlighting are shallow-cloned from each repository's default branch into the user's data directory without pinning a tag.

Pixi and conda-forge inherit the current shell's `http_proxy`, `https_proxy`, and `no_proxy`. Configure a trusted proxy before setup on restricted networks; do not disable TLS verification.

Use this on a container, managed server, or restricted account that cannot change its login shell:

```sh
./server-setup.sh --skip-shell-change
```

This preserves the account's login shell. On Linux/WSL, chezmoi apply maintains a Bash-to-Zsh bridge at the beginning of `.bashrc`: interactive terminals enter Zsh, commands supplied through `bash -i -c` are forwarded intact to `zsh -lc`, and ordinary non-interactive Bash retains Bash semantics. No sudo is required; see the SSH discussion below.

### Codex desktop SSH: login shells, command forwarding, and CLI paths

This section records behavior observed during an actual investigation, not a guarantee about every desktop version. SSH authentication succeeded, but the app reported `SSH websocket open timed out`; logs contained `zsh: command not found: GET` and WebSocket header names.

**Startup sequence.** sshd starts the account's configured login shell. The inspected desktop version then used a command resembling `"$SHELL" -l -i -c 'payload'` to probe tools and start the remote service/proxy. It did not prefer Bash or fall back to Bash because Zsh was unavailable. Inspect the account with `getent passwd "$(id -un)" | cut -d: -f1,7`. `$SHELL` is inherited environment, not proof of the currently executing interpreter; use `$BASH_VERSION` / `$ZSH_VERSION` for that distinction.

`-l` loads login configuration, `-i` requests interactive initialization, and `-c` executes the supplied command. Interactive initialization does not imply a real terminal. An unconditional `exec zsh -l` in interactive `.bashrc` discards the original `-c` payload. Zsh then reads protocol input as commands, interprets `GET` and request headers, and the WebSocket handshake times out. Keeping every `-c` command in Bash fixes that failure but leaves the service's shell environment set to Bash.

**Repository fix.** On Linux/WSL, `run_onchange_before_configure-bash-ssh.sh.tmpl` prepends a managed block from `.chezmoitemplates/bash-ssh.sh` before Bash's non-interactive early return:

| Session | Behavior |
| --- | --- |
| Non-interactive Bash / ordinary SSH command | Expose Pixi, fnm, pnpm and local CLI paths; retain Bash semantics |
| Interactive Bash with `-c` | Export the Zsh path as `SHELL`; `exec "$SHELL" -lc "$BASH_EXECUTION_STRING"` |
| Interactive Bash without `-c` | Export `SHELL`; `exec "$SHELL" -l` |
| Zsh unavailable | Continue in Bash |
| macOS / Windows | Do not run this Bash hook |

The original command is passed as one quoted argument, including an empty command, without splitting or re-evaluation. The bridge does not read stdin, preserving protocol bytes and exit status. Explicitly launched interactive Bash also enters Zsh; use `bash --noprofile --norc` when you need an interactive Bash interpreter.

The system account still starts with Bash, but the desktop's interactive startup stage transfers execution to Zsh and the service inherits its `SHELL`. Explicit application shell settings can override that environment. Existing `.bashrc` content is retained, changes receive a `.bashrc.backup-terminal-setup.*` backup, and reruns do not duplicate the block. Malformed/duplicate markers fail before writing. The hook does not remove custom legacy switching code: inspect obsolete `exec zsh` blocks, including those in `.profile` / `.bash_profile`. Login files must source `.bashrc`; Ubuntu's default `.profile` normally does, but custom login files may not. Interactive handoff happens before remaining Bash configuration, so move required custom environment into the appropriate Zsh startup files.

**CLI versus terminal integration.** Executables are not Zsh-specific; their directories must be in PATH. `.zprofile` initializes login-command paths for fnm/Node, pnpm and Pixi. `zsh -lc` does not load `.zshrc`, so service-required environment must not live only there. `.zshrc` handles interactive functions, aliases and plugins. fzf's `source <(fzf --zsh)` is now guarded by `[[ -t 0 && -t 1 ]]` to avoid `can't change option: zle` without a terminal. The fzf executable remains available for pipelines and `--filter`; real terminals retain key bindings.

**Apply and validate.** Merge the new hook, its template include and the `.zshrc` change into an existing private dotfiles source before running:

```sh
chezmoi apply
bash -lic 'printf "zsh=%s shell=%s\n" "$ZSH_VERSION" "$SHELL"; command -v node pnpm codex'
printf 'SSH_STDIN_OK\n' | bash -lic 'cat'
zsh -lic 'printf "ZSH_INIT_OK\n"' < /dev/null
```

Expect a Zsh version and path, unchanged stdin, and no fzf `zle` error. Install Codex separately; it is not part of the baseline. Bash may still print job-control diagnostics without a terminal; these are distinct from losing the startup payload.

Existing services retain their old environment. Save/finish remote work, restart the remote service using the desktop's supported workflow, then reconnect and open a new terminal. Reconnecting alone may reuse the old service. Use `codex app-server daemon restart` only for a daemon actually managed by that command; do not blindly retry or kill unrelated processes when it reports an unmanaged server. Confirm `connected` and successful initialization in app logs, then inspect `$ZSH_VERSION` / `$SHELL` in the new terminal. Application-specific shell overrides still apply.

For rollback, restore the chosen backup or remove only the marked block, preserving later personal edits, and remove/revert the hook in the source so future changes do not reintroduce it. The fzf guard can be reverted independently. `chezmoi apply --exclude scripts` skips this hook. Because `.bashrc` is maintained by a hook rather than managed as a whole target, ordinary `chezmoi diff/verify` does not fully audit it; inspect the file and backup separately.


To restore your own cross-platform source:

```sh
DOTFILES_REPO='git@github.com:your-account/your-dotfiles-repository.git'
./server-setup.sh --repo "$DOTFILES_REPO"
```

Your private source must use templates and `.chezmoiignore` to distinguish macOS, Linux, and Windows. macOS casks cannot be applied unchanged on other platforms.

## Native Windows

Native Windows uses the PowerShell entry point and does not require WSL or Homebrew. Obtain the repository with an existing Git installation or a GitHub ZIP, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./setup.ps1 -DryRun
./setup.ps1
./doctor.ps1
```

`setup.ps1` invokes Pixi's official PowerShell installer and installs Pixi, Git, chezmoi, and the common CLI baseline under `%USERPROFILE%\.pixi`. It then applies shared Git, Starship, Pixi, uv, and PowerShell configuration. `tmux` remains Linux-only; native Windows uses PowerShell 7 instead of emulating Zsh.

Restore a private source with `./setup.ps1 -Repo 'git@github.com:ACCOUNT/dotfiles.git'`; add `-AgeKeyFile` when it contains age-encrypted files. Windows excludes Unix run scripts during apply and explicitly invokes the managed tool synchronizer:

```powershell
chezmoi apply --exclude scripts
& "$HOME/.myshell/functions/sync-tools.ps1"
chezmoi verify --exclude scripts
```

The Windows workflow does not install fonts yet. Select an already installed Nerd Font in Windows Terminal for Starship glyphs.

## Preview Before Installing

The bundled public starter can be fully previewed:

```sh
./setup.sh --dry-run
./server-setup.sh --dry-run
```

Dry run does not create a chezmoi source directory or modify Home.

When `--repo` refers to a private repository that has not been downloaded, dry run cannot inspect its content because preview mode intentionally does not clone it. Review that repository first or test it in a temporary environment.

## Resulting Environment

| Capability | macOS | Linux/WSL | Native Windows |
|---|---|---|---|
| Platform package manager | Homebrew | apt first, Pixi for gaps; `--user-only` skips apt calls | Pixi global |
| Bootstrap dependencies | Xcode Command Line Tools | apt or administrator-provided | PowerShell; repository from Git/ZIP |
| Interactive shell | Zsh | Zsh | PowerShell 7 |
| Starship, fzf, zoxide | Yes | Yes | Yes |
| Git, chezmoi, jq, ripgrep, fd, bat | Yes | Yes | Yes |
| fnm-managed Node LTS, Corepack, pnpm | Yes | Yes | Yes |
| uv and uv tool manifest | Yes | Yes | Yes |
| Platform CLI manifest | Brewfile | Pixi manifest | Pixi manifest |
| MesloLGS Nerd Font | Automatic | Automatic | Select an installed font manually |
| GUI apps, casks, and AI tools | Recommendations only | Recommendations only | Recommendations only |

### Terminal and CLI choices

| Tool | Role |
|---|---|
| Zsh with small plugins | Completion, history-prefix search, autosuggestions, syntax highlighting |
| Starship | Git, Node, and Python prompt context |
| fzf, fd, ripgrep | History, path, and content search |
| zoxide | Frecency-based directory navigation |
| lsd/eza, bat | Interactive-friendly listings and file output; macOS uses lsd and Pixi platforms use eza |
| Yazi, lazygit | Terminal file and Git interfaces |
| jq, jd, tlrc | JSON, structural diffs, and example-oriented help |
| fnm and Corepack | Node versions and project-owned pnpm versions |
| uv | Python tools and isolated runtimes |

### Starship and fonts

The current Starship theme uses Nerd Font glyphs. macOS and Linux/WSL download and verify four `MesloLGS Nerd Font` files from a pinned Nerd Fonts release into the current user's font directory. Native Windows does not install fonts automatically yet. Select `MesloLGS NF` or `MesloLGS Nerd Font` in the terminal, otherwise prompt symbols may render as boxes.

`doctor.sh` checks that the font files exist. Fonts affect presentation only; they do not change shell, Git, or package-manifest behavior.

The public starter does not install or configure specific applications such as cmux, Ghostty, Codex, CodeBuddy, or CC Switch. Optional apps, specialist CLIs, and uv tools are listed under [`recommendations/`](recommendations/README.md). Accounts, tokens, model-provider configuration, and application state belong in private configuration or application-owned storage.

## How It Works

```text
terminal-setup installer
  ├─ prepare platform prerequisites
  ├─ initialize the public starter or a private chezmoi source
  └─ run chezmoi apply
          │
          ├─ render shell/CLI configuration into Home
          ├─ macOS: reconcile Brew/uv through run_onchange
          ├─ Linux/WSL: reconcile Pixi/uv through run_onchange
          └─ Windows: reconcile Pixi/uv through sync-tools.ps1, then verify
```

Chezmoi maintains two directions:

- **Source state**: normally `~/.local/share/chezmoi`, versioned with Git.
- **Target state**: files under Home, read by shells and applications.

| Intent | Direction |
|---|---|
| Write repository configuration into Home | `chezmoi apply` |
| Add a new Home file to source state | `chezmoi add TARGET` |
| Capture edits made to an existing managed target | `chezmoi re-add TARGET` |
| Inspect pending changes | `chezmoi diff` |
| Confirm target state matches source | `chezmoi verify` |

### Chezmoi features used

| Feature | Purpose |
|---|---|
| Source attributes | `dot_`, `private_`, `encrypted_`, and `executable_` encode paths, permissions, encryption, and executable mode |
| Templates | Render by OS, architecture, and Home directory |
| `.chezmoiignore` | Exclude documentation, caches, runtime state, and platform-specific targets |
| `run_onchange` | Reconcile tools when a manifest hash changes |
| age | Let private derivative repositories store ciphertext only |
| `status/diff/verify` | Detect drift before apply and verify the result |

The repository README, license, tests, and installers are not applied to Home. Only `starter/` acts as the bundled public chezmoi source.

## Bidirectional Package-Manifest Synchronization

The Homebrew, Pixi, and uv manifests have both a Home target state and a chezmoi source state:

| Manifest | Home target | Public starter source |
|---|---|---|
| Homebrew | `~/.Brewfile` | `starter/dot_Brewfile` |
| Pixi CLI | `~/.myshell/pixi-tools.toml` | `starter/dot_myshell/pixi-tools.toml` |
| uv tools | `~/.myshell/uv-tools.toml` | `starter/dot_myshell/uv-tools.toml` |

The starter keeps extensionless commands autoloaded by Zsh in `~/.myshell/bin` and standalone Shell scripts with extensions in `~/.myshell/functions`. `.zshrc` autoloads only extensionless files from `bin`, so `*.sh` and `*.ps1` files are never mistaken for Zsh function bodies.

On macOS/Linux/WSL, `env-sync` inventories Brew taps, top-level Formulae, casks, and uv receipts and captures the managed Pixi declaration. Casks from non-`homebrew/cask` sources are written with their tap-qualified names (for example, `stablyai/orca/orca`) to avoid resolving duplicate tokens to the wrong source. Pixi caches, environments, and its solved internal manifest are runtime state and are not copied into chezmoi. The command never stages, commits, or pushes.

```text
installed state → env-sync → Home target manifests → chezmoi add → chezmoi source manifests
```

Recovery uses the opposite direction. macOS/Linux/WSL use `run_onchange` to invoke Brew or Pixi plus uv. Native Windows excludes Unix scripts and calls `sync-tools.ps1` explicitly:

```text
Git/chezmoi source manifests → chezmoi apply → Home target manifests → platform synchronizer → installed state
```

The `run_onchange_*.sh.tmpl` files are Unix-only special executable source entries, not ordinary scripts copied permanently into Home. Windows uses the explicitly invoked managed `sync-tools.ps1`. Git synchronizes declarations and script sources, never Pixi/uv caches, tool environments, downloaded Python builds, or Homebrew downloads.

## Why `run_onchange` Keeps Packages Synchronized

The script template embeds the manifest SHA-256 in its rendered output:

```text
# Pixi tools hash: {{ include "dot_myshell/pixi-tools.toml" | sha256sum }}
```

Chezmoi records the rendered script state:

- The first apply runs because no execution record exists.
- An unchanged manifest renders identically and is skipped.
- Adding or removing an entry changes the hash and triggers another run.

The default policy installs missing tools without removing extras. Pixi gives each CLI an isolated global environment and exposes commands through `~/.pixi/bin`. To make the machine strictly match the manifests, inspect the cleanup scope and opt in explicitly:

```sh
./setup.sh --prune
```

On a server:

```sh
./server-setup.sh --prune
```

Native Windows uses `./setup.ps1 -Prune`. Pruning covers Brew Formulae, Pixi global environments, and uv tools; it does not remove casks, taps, Pixi caches, or project environments. Use it only after reviewing the manifest difference.

The public starter's `~/.myshell/uv-tools.toml` declares only unpinned `ruff`. Tools such as `determined` and `harlequin` live in [`recommendations/uv-tools.md`](recommendations/uv-tools.md) and are not installed automatically. The manifest is parsed and installed only by the `run_onchange` hook during `chezmoi apply`; it is never loaded at Zsh startup and does not copy uv caches, tool environments, or downloaded Python builds.

## Node and pnpm Ownership

```text
fnm → install and switch Node
Corepack → provide and select pnpm
node_modules/.pnpm → project dependency layout
pnpm store → reconstructible content-addressed cache
PNPM_HOME → global pnpm command directory
```

Chezmoi synchronizes declarations and shell initialization only. Node installations, pnpm stores, caches, and project dependencies remain reconstructible runtime state.

## Optional age Encryption

The public repository contains no recipient, identity, or example ciphertext. Enable age inside your own private chezmoi source:

```sh
./scripts/enable-age.sh
./scripts/add-secret.sh ~/.ssh/config
```

`encryption = "age"` selects the encryption backend; it does not decide which files are sensitive. Add sensitive targets explicitly with `--encrypt` or `add-secret.sh`.

`private_` controls target permissions only. `encrypted_*.age` indicates ciphertext stored in Git. Targets under Home remain plaintext so applications can read them.

## Daily Maintenance

Inspect the current state:

```sh
./doctor.sh
chezmoi status
chezmoi diff
```

Preview and apply changes:

```sh
chezmoi apply --dry-run --verbose
chezmoi apply
chezmoi verify
```

Capture the managed package declarations into the local chezmoi source:

```sh
env-sync
```

Linux/WSL captures the Pixi declaration and uv receipts; macOS also captures the complete Brewfile. Existing uv constraints and Python policy are preserved. Native Windows uses `setup.ps1` and `sync-tools.ps1` instead of the Zsh `env-sync` command. Publishing remains a separate Git operation.

Complete public installer options:

```text
--repo URL            use an existing chezmoi repository
--age-key-file PATH   import an age identity
--prune               remove undeclared Formulae, Pixi environments, and uv tools
--user-only           Linux/WSL user-only installation; skip apt and login-shell changes
--skip-shell-change   preserve the current login shell
--dry-run             preview only
```

Native Windows uses the PowerShell parameters `-Repo`, `-AgeKeyFile`, `-Prune`, and `-DryRun`.

## Full Recovery Backup

```sh
./scripts/full-backup.sh /path/to/private/backup-directory
```

The archive contains the full source and Git state, decrypted managed targets, local chezmoi configuration, the age identity, status snapshots, and a SHA-256 manifest. SSH private keys that are not managed by chezmoi are not included and require a separate secure backup.

It is intentionally unencrypted and must remain on a private NAS, offline disk, or another controlled location. Never upload it to a public repository.

## Public Repository Security Boundary

Never publish age/SSH private keys, private repository addresses, host inventories, laboratory endpoints, Clash nodes or subscriptions, tokens, cookies, OAuth state, model credentials, NAS details, or personal absolute paths.

Before publishing:

```sh
./tests/test.sh
git diff --cached --check
```

Tests cover shell syntax, platform detection, template rendering, isolated apply, manifest safety, age, full backups, installer previews, and secret scanning.

## Project Layout

```text
terminal-setup/
├── setup.sh                 # main macOS/Linux installer
├── setup.ps1                # native Windows PowerShell installer
├── server-setup.sh          # Linux/WSL entry point
├── bootstrap.sh             # temporary clone and installer launcher
├── doctor.sh                # post-install health check
├── doctor.ps1               # native Windows health check
├── lib/                     # platform detection and shared functions
├── scripts/                 # age and full-backup tools
├── starter/                 # bundled public chezmoi source state
└── tests/                   # isolated tests and security checks
```

## Acknowledgements and License

The beginner-oriented documentation structure was inspired by [lewislulu/terminal-setup](https://github.com/lewislulu/terminal-setup). Installation, configuration, manifests, age, backups, and server behavior are independently implemented.

MIT License.
