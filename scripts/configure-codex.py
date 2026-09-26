#!/usr/bin/env python3
"""Repair server shell discovery and optionally configure unsandboxed Codex."""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

try:
    import tomllib
except ImportError:
    sys.exit("Python 3.11+ is required. No files were changed.")


ENVIRONMENT = '''# Shared Bash/Zsh environment for non-interactive Codex connections.
export PIXI_HOME="${PIXI_HOME:-$HOME/.pixi}"
export FNM_HOME="${FNM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"
export PNPM_HOME="${PNPM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pnpm}"
for _terminal_setup_dir in "$HOME/.local/bin" "$PIXI_HOME/bin" "$FNM_HOME" "$PNPM_HOME" "$PNPM_HOME/bin"; do
    case ":$PATH:" in
        *":$_terminal_setup_dir:"*) ;;
        *) PATH="$_terminal_setup_dir:$PATH" ;;
    esac
done
export PATH
unset _terminal_setup_dir
if command -v fnm >/dev/null 2>&1; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        eval "$(fnm env --shell zsh)"
    elif [ -n "${BASH_VERSION:-}" ]; then
        eval "$(fnm env --shell bash)"
    fi
fi
'''

START = "# >>> terminal-setup: Codex SSH environment >>>"
END = "# <<< terminal-setup: Codex SSH environment <<<"
LEGACY_START = "# >>> terminal-setup: Bash environment for non-interactive SSH clients >>>"
LEGACY_END = "# <<< terminal-setup <<<"
BRIDGE_START = "# >>> terminal-setup: Bash SSH environment >>>"
BRIDGE_END = "# <<< terminal-setup: Bash SSH environment <<<"
HOOK = f'''{START}
if [ -r "$HOME/.config/terminal-setup/codex-env.sh" ]; then
    . "$HOME/.config/terminal-setup/codex-env.sh"
fi
{END}
'''

SWITCH_START = "# >>> switch to zsh as default interactive shell >>>"
SWITCH_END = "# <<< switch to zsh as default interactive shell <<<"
SWITCH = f'''{SWITCH_START}
# Preserve explicit commands and leave stdin available for remote protocols.
if [[ $- == *i* && -z "${{ZSH_VERSION:-}}" && -x "$HOME/.pixi/bin/zsh" ]]; then
    export SHELL="$HOME/.pixi/bin/zsh"
    if [[ -n "${{BASH_EXECUTION_STRING+x}}" ]]; then
        exec "$SHELL" -lc "$BASH_EXECUTION_STRING"
    fi
    exec "$SHELL" -l
fi
{SWITCH_END}
'''


def replace_block(text, start, end, replacement=""):
    """Only edit known managed blocks; fail before writing on broken markers."""
    starts = list(re.finditer(r"^" + re.escape(start) + r"\r?$", text, re.M))
    ends = list(re.finditer(r"^" + re.escape(end) + r"\r?$", text, re.M))
    if not starts and not ends:
        return text
    if len(starts) != 1 or len(ends) != 1 or starts[0].start() >= ends[0].start():
        raise ValueError(f"Ambiguous shell block: {start}. Repair its markers first.")
    finish = ends[0].end()
    if text[finish:finish + 1] == "\n":
        finish += 1
    return text[:starts[0].start()] + replacement + text[finish:]


def shell_config(text, bashrc=False):
    text = replace_block(text, START, END)
    if bashrc:
        text = replace_block(text, LEGACY_START, LEGACY_END)
        # Preserve the user's decision to switch shells; never introduce it.
        text = replace_block(text, SWITCH_START, SWITCH_END, SWITCH)
        # The starter's chezmoi hook already owns this Bash initialization.
        bridge_starts = list(re.finditer(r"^" + re.escape(BRIDGE_START) + r"\r?$", text, re.M))
        bridge_ends = list(re.finditer(r"^" + re.escape(BRIDGE_END) + r"\r?$", text, re.M))
        if bridge_starts or bridge_ends:
            if len(bridge_starts) != 1 or len(bridge_ends) != 1 or bridge_starts[0].start() >= bridge_ends[0].start():
                raise ValueError("Ambiguous Bash SSH environment block. Repair its markers first.")
            return text
    if text.startswith("#!"):
        first, _, rest = text.partition("\n")
        return first + "\n" + HOOK + rest
    return HOOK + text


def codex_config(text):
    """Edit whole TOML statements, preserving unrelated text and nested tables."""
    original = tomllib.loads(text)
    replaced = {"sandbox_mode", "approval_policy", "default_permissions",
                "sandbox_workspace_write", "permissions"}
    output = []
    section = None
    buffer = ""
    for line in text.splitlines(keepends=True):
        buffer += line
        try:
            statement = tomllib.loads(buffer)
        except tomllib.TOMLDecodeError:
            # Multiline strings, arrays, and inline tables must stay intact.
            continue
        if buffer.lstrip().startswith("["):
            section = next(iter(statement))
        if section not in replaced and not (section is None and replaced.intersection(statement)):
            output.append(buffer)
        buffer = ""
    if buffer.strip():
        raise ValueError("Could not safely split the TOML configuration; no files changed.")
    result = ('sandbox_mode = "danger-full-access"\n'
              'approval_policy = "on-request"\n' + "".join(output))
    expected = {key: value for key, value in original.items() if key not in replaced}
    expected.update(sandbox_mode="danger-full-access", approval_policy="on-request")
    if tomllib.loads(result) != expected:
        raise ValueError("TOML preservation check failed; no files changed.")
    return result


def write_atomic(path, text, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".codex-setup-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(text)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=(
        "Fix server Bash/Zsh paths for Codex. Requires Python 3.11+. "
        "No sudo, package installation, or account login-shell changes."))
    parser.add_argument("--no-sandbox", action="store_true", help=(
        "also set danger-full-access and on-request; commands gain all access "
        "available to your user account"))
    parser.add_argument("--dry-run", action="store_true", help="list changes without writing files")
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("this helper supports Linux/WSL servers only")

    home = Path.home()
    changes = []

    def plan(path, transform):
        # Follow existing chezmoi symlinks without replacing the links themselves.
        target = path.resolve()
        if any(item[0] == target for item in changes):
            raise ValueError(f"Multiple configuration paths resolve to {target}")
        old = None
        if target.exists():
            with target.open(encoding="utf-8", newline="") as stream:
                old = stream.read()
        new = transform(old or "")
        if old != new:
            mode = stat.S_IMODE(target.stat().st_mode) if old is not None else 0o600
            changes.append((target, old, new, mode))

    plan(home / ".config/terminal-setup/codex-env.sh", lambda _: ENVIRONMENT)
    plan(home / ".bashrc", lambda text: shell_config(text, bashrc=True))
    # Use the file Bash actually reads, without shadowing an existing .profile.
    login = next((home / name for name in (".bash_profile", ".bash_login", ".profile")
                  if (home / name).exists()), home / ".profile")
    plan(login, shell_config)
    # Zsh reads .zshenv for both login and non-login SSH commands.
    zsh_dir = Path(os.environ.get("ZDOTDIR") or home).expanduser()
    plan(zsh_dir / ".zshenv", shell_config)
    if args.no_sandbox:
        config_dir = Path(os.environ.get("CODEX_HOME") or home / ".codex").expanduser()
        plan(config_dir / "config.toml", codex_config)

    if not changes:
        print("Already configured; no files changed.")
        return
    for path, old, _, _ in changes:
        print(f"{'Would' if args.dry_run else 'Will'} {'create' if old is None else 'update'}: {path}")
    if args.no_sandbox:
        print("Codex will run without a local sandbox, with your user's permissions (not root).")
    if args.dry_run:
        print("Dry run complete; no files changed.")
        return

    # Back up every original before the first write. Backups may contain secrets.
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
    backup_root = state / "terminal-setup/codex-backups"
    backup_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ-")
    backup = Path(tempfile.mkdtemp(prefix=stamp, dir=backup_root))
    records = []
    for index, (path, old, _, mode) in enumerate(changes):
        name = f"{index}-{path.name}" if old is not None else None
        if name:
            write_atomic(backup / name, old, 0o600)
        records.append({"target": str(path), "backup": name, "mode": mode})
    write_atomic(backup / "manifest.json", json.dumps(records, indent=2) + "\n", 0o600)
    print(f"Original files and their target paths: {backup}")
    written = []
    try:
        for change in changes:
            path, old, new, mode = change
            write_atomic(path, new, mode)
            written.append(change)
    except OSError:
        for path, old, _, mode in reversed(written):
            if old is None:
                path.unlink()
            else:
                write_atomic(path, old, mode)
        raise
    print("Configured. Reconnect SSH / the desktop remote session, or restart Codex CLI.")
    print("Check remotely: command -v node; command -v codex; codex --version")
    if args.no_sandbox:
        print("Desktop permission selections or a selected Codex profile may override config.toml.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f"Error: {error}")
