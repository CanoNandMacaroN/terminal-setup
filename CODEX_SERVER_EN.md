# Server Codex problems and fixes

[Back to README](README_EN.md#server-codex) · [中文](CODEX_SERVER.md)

Run these commands **on the Linux/WSL server executing Codex**. Python 3.11+, Node, and Codex must already be installed. The helper needs no sudo and installs no packages.

## Fix both SSH discovery and bwrap errors

From the `terminal-setup` repository:

```sh
./scripts/configure-codex.sh --no-sandbox
```

This repairs Bash/Zsh tool paths and configures Codex for full access as your current user, with approvals available on request. **It disables the local Codex sandbox: file access is no longer confined to the project, but it does not grant root privileges.** Not every command requires approval.

To preview the files that would change:

```sh
./scripts/configure-codex.sh --no-sandbox --dry-run
```

Reconnect SSH / the desktop remote session afterward. For the CLI, exit with `/quit` and start `codex` again.

<a id="ssh-shell"></a>

## Problem: Codex works in a terminal, but a remote connection cannot find node or codex

**Fix: repair only the shell environment.**

```sh
./scripts/configure-codex.sh
```

A common cause is a Bash login account that switches to Zsh only for interactive terminals. Non-interactive remote commands never reach the Zsh switch at the bottom of `.bashrc`, so they miss Node/pnpm paths configured only in `.zshrc` or `.zprofile`.

The helper writes Pixi, fnm, pnpm, and `~/.local/bin` initialization to `~/.config/terminal-setup/codex-env.sh`, then loads it from:

- The beginning of `.bashrc`, before any non-interactive `return`.
- If `.bashrc` already has this repository's chezmoi-managed Bash SSH block, the helper keeps it instead of inserting a second initialization block.
- Bash's active login file: the first existing `.bash_profile`, `.bash_login`, or `.profile`; it creates `.profile` when none exists.
- `.zshenv`, covering non-interactive Zsh commands too; it respects an exported `ZDOTDIR`.

It uses `fnm env --shell bash` or `--shell zsh` as appropriate, without sourcing Zsh configuration from Bash. If `.bashrc` already contains this project's marked interactive Zsh switch, it updates that block to preserve explicit commands without consuming stdin. It does not introduce a switch or change the account's login shell.

Check from the client, substituting your SSH Host alias:

```sh
ssh your-server 'command -v node; command -v codex; node --version; codex --version'
```

If Node is still missing, use `fnm list` to check its installation and default version. The helper fixes paths; it cannot supply missing Node or Codex installations.

<a id="bwrap"></a>

## Problem: Codex tool commands fail with bwrap permission errors

Typical errors:

```text
bwrap: setting up uid map: Permission denied
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

**Fix: if you cannot change system policy and accept full access, run:**

```sh
./scripts/configure-codex.sh --no-sandbox
```

These errors mean the system denied permissions needed to create the sandbox. In this Ubuntu 24.04 incident, diagnostics pointed to AppArmor restrictions on unprivileged user namespaces. A user-local `bwrap --version` worked, but sandbox creation still failed; reinstalling bwrap did not fix it.

The helper writes these top-level settings to the server's `~/.codex/config.toml`, or to `config.toml` under an overridden `CODEX_HOME`:

```toml
sandbox_mode = "danger-full-access"
approval_policy = "on-request"
```

Model, provider, and other unrelated settings are preserved. To avoid mixing permission systems, it removes top-level `default_permissions`, `[permissions]` and its subtables, and `[sandbox_workspace_write]` and its subtables, after backing up the original. Named profiles are unchanged; a selected profile or desktop permission selection can still override these defaults.

If the desktop connection reports the same error, select Full access for that remote session and reconnect. The helper cannot override organization policy that prohibits full access.

<a id="verify"></a>

## Problem: the session still uses old settings

1. Disconnect and reconnect the desktop remote session. Reopening a local terminal does not necessarily restart remote Codex.
2. Exit the CLI with `/quit`, then run `codex` again. To explicitly select these permissions:

   ```sh
   codex --sandbox danger-full-access --ask-for-approval on-request
   ```

3. Inspect permissions with `/status`, then ask Codex to run `pwd` and `id`. Discovering the Codex executable and executing Codex tool commands are separate checks.

## Backups and repeated runs

Before editing, the helper backs up original files and prints the backup directory. It defaults to `~/.local/state/terminal-setup/codex-backups/`, respecting `XDG_STATE_HOME` when set. Its `manifest.json` maps each backup to the original path; `backup: null` means the target did not previously exist. Backups may contain private settings and should not be committed.

Repeating the same command does not duplicate configuration blocks. Existing symlinks are preserved and their targets updated. Invalid TOML or damaged managed markers stop the operation before changes are written. For chezmoi-managed files, inspect `chezmoi diff` and save the intended changes back to your private source state.

References: [OpenAI configuration](https://developers.openai.com/codex/config-reference) · [Permissions](https://learn.chatgpt.com/docs/permissions)
