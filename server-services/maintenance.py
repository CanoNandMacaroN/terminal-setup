#!/usr/bin/env python3
# terminal-setup server-services: reversible client runtime maintenance
"""Preview or reversibly archive selected Linux Codex/CodeBuddy runtime files."""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import sys
import uuid

ARCHIVES = ".terminal-setup-archives"


def checked(path):
    path = Path(path).expanduser().absolute()
    if ".." in path.parts or path in (Path("/"), Path.home()):
        raise ValueError(f"Use a dedicated application directory: {path}")
    if any(parent.is_symlink() for parent in (path, *path.parents)):
        raise ValueError(f"Refusing a symlink path: {path}")
    return path


def active_clients(client, proc=Path("/proc")):
    matches = []
    if not proc.is_dir():
        raise ValueError("Cannot check client processes without /proc")
    for directory in proc.iterdir():
        if not directory.name.isdigit() or int(directory.name) == os.getpid():
            continue
        try:
            if directory.stat().st_uid != os.getuid():
                continue
            command = (directory / "cmdline").read_bytes().split(b"\0")
            # Limit inspection to executable/script positions, not arbitrary prompts.
            positions = [p.decode(errors="replace") for p in command[:3]]
            if client == "codex":
                found = any(re.search(r"(?:^|/)(?:codex|codex-cli|codex-app-server)(?:\.js)?$", p, re.I) for p in positions)
            else:
                found = any("/.codebuddy-server" in p or Path(p).name in ("codebuddy", "codebuddy-server", "CodeBuddy") for p in positions)
            if found:
                matches.append(directory.name)
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            raise ValueError(f"Cannot inspect own process {directory.name}; close clients before retrying")
    return matches


def require_stopped(client):
    running = active_clients(client)
    if running:
        raise ValueError(f"Close {client} and disconnect its remote sessions first (running PIDs: {', '.join(running)})")


def targets(client, history):
    home = Path.home()
    if client == "codex":
        root = checked(os.environ.get("CODEX_HOME") or home / ".codex")
        names = ["log", "cache", "tmp", "shell_snapshots"]
        if history:
            names += ["sessions", "archived_sessions", "history.jsonl", "session_index.jsonl"]
        groups = [(root, names)]
    else:
        root = checked(os.environ.get("CODEBUDDY_SERVER_HOME") or home / ".codebuddy-server-cn")
        names = ["data/logs"]
        names += [p.name for p in root.glob("*.log")]
        if history:
            names += ["data/User/History", "data/User/workspaceStorage",
                      "data/User/globalStorage/tencent-cloud.coding-copilot/genie-history",
                      "data/User/globalStorage/tencent-cloud.coding-copilot/message-queue"]
        groups = [(root, names)]
        if history:
            groups.append((checked(os.environ.get("CODEBUDDY_HOME") or home / ".codebuddy"), ["expert-history.json"]))
    result = []
    for root, names in groups:
        entries = []
        for name in names:
            path = checked(root / name)
            if path.exists():
                if not path.is_file() and not path.is_dir():
                    raise ValueError(f"Unsupported runtime entry: {path}")
                entries.append(name)
        checked(root / ARCHIVES)
        if entries:
            result.append((root, entries))
    return result


def manifest_write(archive, record):
    temporary = archive / ".manifest.tmp"
    with temporary.open("x", encoding="utf-8") as stream:
        json.dump(record, stream, indent=2)
        stream.write("\n")
    temporary.replace(archive / "manifest.json")


def archive_runtime(client, history, apply):
    groups = targets(client, history)
    for root, entries in groups:
        for name in entries:
            print(f"Archive: {root / name}")
    if not groups:
        print("No matching runtime files.")
        return
    if not apply:
        print("Preview only. Close the client, then add --apply to archive these entries.")
        return
    require_stopped(client)
    tag = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8]
    moved = []
    try:
        for root, entries in groups:
            archive = root / ARCHIVES / tag
            archive.mkdir(parents=True, mode=0o700)
            manifest_write(archive, {"schema": 1, "client": client, "entries": entries})
            print(f"Recovery archive: {archive}")
            for name in entries:
                source = checked(root / name)
                destination = archive / "files" / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                # Archive inside the same app root: no cross-filesystem copy/delete.
                source.rename(destination)
                moved.append((source, destination))
    except (OSError, ValueError):
        for source, destination in reversed(moved):
            if not source.exists():
                destination.rename(source)
        raise
    print("Selected runtime files archived. Credentials, configuration, databases, and worktrees were not changed.")


def restore(archive, apply):
    archive = checked(archive)
    if archive.parent.name != ARCHIVES or not archive.is_dir():
        raise ValueError("Select a recovery directory printed by this helper")
    root = checked(archive.parent.parent)
    metadata = checked(archive / "manifest.json")
    record = json.loads(metadata.read_text())
    if record.get("schema") != 1 or record.get("client") not in ("codex", "codebuddy"):
        raise ValueError("Unrecognized recovery manifest")
    entries = record.get("entries")
    if not isinstance(entries, list) or not entries or any(not isinstance(n, str) for n in entries):
        raise ValueError("Invalid recovery entries")
    planned = []
    for name in entries:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or relative == Path(".") or ARCHIVES in relative.parts:
            raise ValueError("Unsafe recovery entry")
        source, destination = checked(archive / "files" / relative), checked(root / relative)
        if not source.exists():
            continue
        if destination.exists():
            raise ValueError(f"New runtime data exists: {destination}; move it aside before restoring")
        planned.append((source, destination))
    for source, destination in planned:
        print(f"Restore: {source} -> {destination}")
    if not apply:
        print("Preview only; add --apply to restore.")
        return
    require_stopped(record["client"])
    moved = []
    try:
        for source, destination in planned:
            destination.parent.mkdir(parents=True, exist_ok=True)
            source.rename(destination)
            moved.append((source, destination))
    except OSError:
        for source, destination in reversed(moved):
            destination.rename(source)
        raise
    print("Archived entries restored; recovery manifest retained.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("codex", "codebuddy", "restore"):
        sub = subparsers.add_parser(name)
        choice = sub.add_mutually_exclusive_group()
        choice.add_argument("--apply", action="store_true", help="apply the previewed archive/restore operation")
        choice.add_argument("--dry-run", action="store_true", help="preview only (the default)")
        if name == "restore":
            sub.add_argument("--archive", required=True)
        else:
            sub.add_argument("--include-history", action="store_true", help="also archive listed history directories/files")
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("Linux/WSL server maintenance only")
    os.umask(0o077)
    if args.command == "restore":
        restore(args.archive, args.apply)
    else:
        archive_runtime(args.command, args.include_history, args.apply)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f"Error: {error}")
