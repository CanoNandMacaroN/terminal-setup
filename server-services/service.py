#!/usr/bin/env python3
# terminal-setup server-services: portable user storage and backup service
"""Independent user-level storage setup, rsync operations, and optional timer."""

import argparse
from contextlib import contextmanager
import datetime
import getpass
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
from string import Template
import uuid

try:
    import tomllib
except ImportError:
    sys.exit("Python 3.11+ is required; no files changed.")

MARKER = "terminal-setup server-services"
UNIT = "terminal-setup-backup"
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*\Z")
STAMP = re.compile(r"\d{8}T\d{12}Z-[a-f0-9]{8}\Z")


def fail(message):
    raise ValueError(message)


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ-") + uuid.uuid4().hex[:8]


def checked_name(value):
    if not isinstance(value, str) or not NAME.fullmatch(value):
        fail(f"Expected a simple directory/instance name, got {value!r}")
    return value


def path_value(value):
    if not isinstance(value, str) or any(c in value for c in "\n\r\0"):
        fail("Paths must be strings without control characters")
    environment = {"USER": getpass.getuser(), **os.environ}
    value = Template(value).substitute(environment)
    path = Path(value).expanduser()
    if not path.is_absolute():
        fail(f"Use an absolute path: {path}")
    # Normalize '..' without following symlinks; real_directory must see them.
    return Path(os.path.normpath(str(path)))


def real_directory(path, required=False):
    """Check every component so operations cannot follow a replaced symlink."""
    for part in (path, *path.parents):
        if part.is_symlink():
            fail(f"Directory may not be a symlink: {part}")
        if part.exists() and not part.is_dir():
            fail(f"Expected a directory: {part}")
    if required and not path.is_dir():
        fail(f"Missing directory (initialize/mount storage first): {path}")


def atomic_write(path, text, mode=0o600):
    real_directory(path.parent)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        fail(f"Refusing to replace non-regular file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".server-services-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Service:
    def __init__(self, args):
        self.args = args
        self.config_path = Path(args.config).expanduser().absolute()
        # A broken or removed storage config must not prevent stopping the timer.
        if args.command == "disable-timer":
            self.calendar = "daily"
            return
        self.text = self.config_path.read_text()
        config = tomllib.loads(self.text)
        allowed = {"paths": {"shared_mount", "shared_root", "data_mount", "data_root", "local_root", "links_root"},
                   "storage": {"require_mounts", "instance"},
                   "sync": {"working_dirs", "snapshot_dirs"},
                   "backup": {"keep_snapshots", "include_data", "calendar"}}
        for section, values in config.items():
            if section not in allowed or not isinstance(values, dict) or set(values) - allowed[section]:
                fail(f"Unknown configuration entries in {section}")
        self.paths = {key: path_value(config["paths"][key]) for key in allowed["paths"]}
        self.shared = self.paths["shared_root"]
        self.data = self.paths["data_root"]
        self.local = self.paths["local_root"]
        self.links = self.paths["links_root"]
        roots = [self.shared, self.data, self.local, self.links]
        for i, root in enumerate(roots):
            if root in (Path("/"), Path.home().resolve()):
                fail(f"Use a dedicated subdirectory, not {root}")
            for other in roots[i + 1:]:
                if root.is_relative_to(other) or other.is_relative_to(root):
                    fail(f"Storage roots must not overlap: {root}, {other}")
        self.instance = checked_name(config.get("storage", {}).get("instance", socket.gethostname()))
        self.mounts = config.get("storage", {}).get("require_mounts", True)
        self.working = self.names(config.get("sync", {}).get("working_dirs", ["code", "tasks"]))
        self.snapdirs = self.names(config.get("sync", {}).get("snapshot_dirs", ["scripts", "docs"]))
        reserved = {"backups", "dataset", "env", "logs", "data"}
        if set(self.working + self.snapdirs) & reserved or set(self.working) & set(self.snapdirs):
            fail("Working/snapshot names must be disjoint and not use reserved storage names")
        backup = config.get("backup", {})
        self.keep = backup.get("keep_snapshots", 10)
        self.include_data = backup.get("include_data", False)
        self.calendar = backup.get("calendar", "daily")
        if type(self.mounts) is not bool or type(self.include_data) is not bool:
            fail("require_mounts and include_data must be booleans")
        if type(self.keep) is not int or self.keep < 1:
            fail("keep_snapshots must be an integer >= 1")
        if not isinstance(self.calendar, str) or not self.calendar.strip() or any(c in self.calendar for c in "\n\r\0%"):
            fail("Invalid systemd calendar value")
        self.archive = self.shared / "backups/server-services" / self.instance
        self.snapshots = self.archive / "snapshots"
        self.tag = stamp()

    @staticmethod
    def names(values):
        if not isinstance(values, list) or not values or any(not isinstance(v, str) for v in values) or len(values) != len(set(values)):
            fail("Directory lists must be nonempty and contain unique names")
        return [checked_name(value) for value in values]

    def check_storage(self, initialized=True):
        for prefix in ("shared", "data"):
            mount, root = self.paths[prefix + "_mount"], self.paths[prefix + "_root"]
            if root == mount or not root.is_relative_to(mount):
                fail(f"{prefix}_root must be a subdirectory of {mount}")
            real_directory(mount, required=True)
            permissions = mount.stat().st_mode
            if permissions & 0o022 and not permissions & 0o1000:
                fail(f"Writable storage mount needs a sticky bit to protect user directories: {mount}")
            if permissions & 0o022 and mount.stat().st_uid not in (0, os.getuid()):
                fail(f"Writable storage mount must be owned by root or the current user: {mount}")
            if self.mounts and not os.path.ismount(mount):
                fail(f"Storage is not mounted: {mount}; refusing to write to the underlying directory")
            parent = root.parent
            while parent != mount:
                real_directory(parent, required=initialized)
                if parent.exists() and (parent.stat().st_uid not in (0, os.getuid()) or parent.stat().st_mode & 0o022):
                    fail(f"Storage parent must be owned by root/current user and not writable by others: {parent}")
                parent = parent.parent
        for root in (self.shared, self.data, self.local, self.links):
            real_directory(root, required=initialized)
            if root.exists():
                if root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o022:
                    fail(f"Storage root must be owned by the current user and not writable by others: {root}")
        real_directory(self.archive)
        if self.archive.exists() and (self.archive.stat().st_uid != os.getuid() or self.archive.stat().st_mode & 0o022):
            fail(f"Backup root must be owned by the current user and not writable by others: {self.archive}")
        if not shutil.which("rsync"):
            fail("rsync is required; install the terminal baseline first")

    @contextmanager
    def lock(self, instance=False):
        lock = (self.archive if instance else self.shared) / ".terminal-setup-sync.lock"
        try:
            lock.mkdir()
        except FileExistsError:
            fail(f"Storage is locked: {lock}. Check owner.json; remove the lock only after its process has stopped.")
        try:
            atomic_write(lock / "owner.json", json.dumps({"host": socket.gethostname(), "pid": os.getpid()}) + "\n")
            yield
        finally:
            (lock / "owner.json").unlink(missing_ok=True)
            lock.rmdir()

    def rsync(self, source, target, *, history=None, previous=None, preview=False):
        command = ["rsync", "-a", "--human-readable", "--itemize-changes"]
        if self.args.mirror:
            command.append("--delete")
        if history is not None:
            command += ["--backup", f"--backup-dir={history}"]
        if previous is not None:
            command.append(f"--link-dest={previous}")
        if preview:
            command.append("--dry-run")
        command += ["--", str(source) + "/", str(target) + "/"]
        print(shlex.join(command), flush=True)
        # rsync cannot preview into missing ancestor directories without creating them.
        if preview and not target.parent.is_dir():
            print("Destination parent would be created; showing command only.")
            return
        if not preview:
            target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(command, check=True)

    def pairs(self, operation):
        if operation == "backup-data":
            return [(self.data / name, self.shared / "dataset" / self.instance / name,
                     self.archive / "trash" / self.tag / "dataset" / name) for name in ("input", "output")]
        if operation == "pull":
            return [(self.shared / name, self.local / name,
                     self.local / ".sync-trash" / self.tag / name) for name in self.working]
        return [(self.local / name, self.shared / name,
                 self.archive / "trash" / self.tag / "push" / name) for name in self.working]

    def validate_pairs(self, pairs):
        for source, target, history in pairs:
            real_directory(source, required=True)
            real_directory(target)
            real_directory(history)
            if self.args.mirror and not self.args.allow_empty and not any(source.iterdir()):
                fail(f"Empty mirror source: {source}. Inspect it, then use --allow-empty if intentional.")

    def sync(self, operation, preview=False):
        pairs = self.pairs(operation)
        self.validate_pairs(pairs)
        for source, target, history in pairs:
            self.rsync(source, target, history=history, preview=preview)

    def previous_snapshot(self):
        real_directory(self.snapshots)
        latest = self.snapshots / "latest"
        if not latest.is_symlink():
            if latest.exists():
                fail(f"Expected a managed snapshot symlink: {latest}")
            return None
        previous = latest.resolve()
        if previous.parent != self.snapshots or not self.is_snapshot(previous):
            fail(f"Invalid latest snapshot: {latest}")
        return previous

    def is_snapshot(self, path):
        if not STAMP.fullmatch(path.name) or path.is_symlink() or not path.is_dir():
            return False
        metadata = path / ".snapshot.json"
        if metadata.is_symlink() or not metadata.is_file():
            return False
        try:
            return json.loads(metadata.read_text()) == {"owner": MARKER, "instance": self.instance}
        except (ValueError, OSError):
            return False

    def snapshot(self, preview=False):
        previous = self.previous_snapshot()
        for name in self.snapdirs:
            real_directory(self.local / name, required=True)
            if previous and ((previous / name).exists() or (previous / name).is_symlink()):
                real_directory(previous / name, required=True)
        staging = self.snapshots / ("." + self.tag + ".partial")
        if not preview:
            staging.mkdir(parents=True)
        for name in self.snapdirs:
            self.rsync(self.local / name, staging / name,
                       previous=previous / name if previous and (previous / name).is_dir() else None, preview=preview)
        if preview:
            print(f"Would publish snapshot and retain the newest {self.keep} completed snapshots.")
            return
        atomic_write(staging / ".snapshot.json", json.dumps({"owner": MARKER, "instance": self.instance}) + "\n")
        final = self.snapshots / self.tag
        staging.rename(final)
        temporary = self.snapshots / (".latest-" + self.tag)
        temporary.symlink_to(final.name)
        temporary.replace(self.snapshots / "latest")
        completed = sorted((p for p in self.snapshots.iterdir() if self.is_snapshot(p)), reverse=True)
        for old in completed[self.keep:]:
            print(f"Prune completed snapshot: {old}")
            shutil.rmtree(old)
        print(f"Snapshot: {final}")

    def operate(self):
        self.check_storage()
        operation = self.args.command
        preview = self.args.dry_run or operation == "status"
        operations = ["pull", "push"] if operation == "status" else [operation]
        if operation == "backup":
            operations = ["snapshot"] + (["backup-data"] if self.include_data else [])
        # Validate all sources/destinations before changing any of them.
        for op in operations:
            if op == "snapshot":
                self.previous_snapshot()
                for name in self.snapdirs:
                    real_directory(self.local / name, required=True)
            else:
                self.validate_pairs(self.pairs(op))

        def run():
            for op in operations:
                self.snapshot(preview) if op == "snapshot" else self.sync(op, preview)

        if preview:
            run()
        else:
            with self.lock(instance=operation not in ("pull", "push")):
                self.check_storage()
                run()

    def install(self):
        self.check_storage(initialized=False)
        shared_names = ["backups", "env", "dataset", "logs", *self.working]
        directories = [self.local, self.links, self.links / "data", self.archive,
                       *[self.local / name for name in self.working + self.snapdirs],
                       *[self.shared / name for name in shared_names],
                       *[self.data / name for name in ("input", "output", "scratch")]]
        links = [(self.links / name, self.shared / name) for name in shared_names]
        links += [(self.links / "data" / name, self.data / name) for name in ("input", "output", "scratch")]
        for directory in directories:
            real_directory(directory)
        for link, target in links:
            if link.is_symlink():
                if link.resolve() != target:
                    fail(f"Existing link points elsewhere: {link}; move it aside before installing")
            elif link.exists():
                fail(f"Existing real file/directory at link location: {link}; it will not be overwritten")
        executable = Path.home() / ".local/bin/server-services"
        outputs = {executable: (Path(__file__).read_text(), 0o700),
                   default_config(): (self.text, 0o600)}
        maintenance = Path(__file__).with_name("maintenance.py")
        if not maintenance.is_file():
            fail("Reinstall from the repository's server-setup.sh --services entry to update both commands")
        outputs[executable.with_name("server-maintenance")] = (maintenance.read_text(), 0o700)
        changes = {}
        for path, (content, mode) in outputs.items():
            real_directory(path.parent)
            if path.is_symlink() or (path.exists() and not path.is_file()):
                fail(f"Refusing to replace non-regular file: {path}")
            old = path.read_text() if path.exists() else None
            if path.name in ("server-services", "server-maintenance") and old is not None and MARKER not in old:
                fail(f"An unrelated executable already exists: {path}")
            if old != content or (path.exists() and path.stat().st_mode & 0o777 != mode):
                changes[path] = (content, mode, old)
        for directory in directories:
            print(f"Ensure directory: {directory}")
        for link, target in links:
            print(f"Ensure link: {link} -> {target}")
        for path in changes:
            print(f"Install: {path}")
        if self.args.dry_run:
            print("Dry run: no files, directories, links, or timers changed.")
            return
        for directory in directories:
            directory.mkdir(parents=True, exist_ok=True)
        self.check_storage()
        with self.lock():
            if any(old is not None for _, _, old in changes.values()):
                backup = Path.home() / ".local/state/terminal-setup/server-services/install-backups" / self.tag
                for path, (_, _, old) in changes.items():
                    if old is not None:
                        atomic_write(backup / path.name, old)
                print(f"Previous module files: {backup}")
            for path, (content, mode, _) in changes.items():
                atomic_write(path, content, mode)
            for link, target in links:
                if not link.is_symlink():
                    link.symlink_to(target, target_is_directory=True)
        print(f"Installed: {executable}. No data was synchronized; no timer was enabled.")

    def timer(self):
        enable = self.args.command == "enable-timer"
        units = Path.home() / ".config/systemd/user"
        service_path, timer_path = units / (UNIT + ".service"), units / (UNIT + ".timer")
        executable = Path.home() / ".local/bin/server-services"
        if enable:
            self.check_storage()
            if not executable.is_file() or MARKER not in executable.read_text():
                fail("Install this module before enabling its timer")
        if not shutil.which("systemctl"):
            fail("systemctl is unavailable; run 'server-services backup' manually or from your scheduler")

        def quote(value):
            # ExecStart's ':' prefix disables $ expansion; escape systemd specifiers.
            value = str(value)
            if any(c in value for c in "\n\r\0"):
                fail("Control characters are not valid in a systemd unit")
            return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'

        command = " ".join(quote(part) for part in (sys.executable, executable, "backup", "--config", self.config_path))
        path = ":".join(str(Path.home() / part) for part in (".local/bin", ".pixi/bin")) + ":/usr/local/bin:/usr/bin:/bin"
        files = {service_path: f'''# {MARKER}
[Unit]
Description=Terminal setup user storage backup

[Service]
Type=oneshot
Environment={quote("PATH=" + path)}
ExecStart=:{command}
UMask=0077
''', timer_path: f'''# {MARKER}
[Unit]
Description=Scheduled terminal setup backup

[Timer]
OnCalendar={self.calendar}
Persistent=true
RandomizedDelaySec=300
Unit={UNIT}.service

[Install]
WantedBy=timers.target
'''}
        real_directory(units)
        if not enable and (not timer_path.is_file() or MARKER not in timer_path.read_text()):
            fail(f"No managed timer found at {timer_path}")
        for file in files:
            if file.is_symlink() or (file.exists() and (not file.is_file() or MARKER not in file.read_text())):
                fail(f"Refusing to replace an unrelated unit: {file}")
        print(f"{'Enable' if enable else 'Disable'} user timer: {UNIT}.timer (backup only; never pull/push)")
        if self.args.dry_run:
            if enable:
                for file, content in files.items():
                    print(f"{file}:\n{content}")
            return
        # Fail before installing unit files if no user manager is available.
        subprocess.run(["systemctl", "--user", "show-environment"], check=True, stdout=subprocess.DEVNULL)
        if enable:
            for file, content in files.items():
                atomic_write(file, content)
            subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
            subprocess.run(["systemctl", "--user", "enable", "--now", UNIT + ".timer"], check=True)
        else:
            subprocess.run(["systemctl", "--user", "disable", "--now", UNIT + ".timer"], check=True)
        print("Inspect runs: journalctl --user -u " + UNIT + ".service")


def default_config():
    return Path.home() / ".config/terminal-setup/server-services.toml"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("install", "status", "pull", "push", "snapshot", "backup-data", "backup", "enable-timer", "disable-timer"):
        sub = commands.add_parser(name)
        sub.add_argument("--config", default=str(default_config()))
        sub.add_argument("--dry-run", action="store_true")
        sub.set_defaults(mirror=False, allow_empty=False)
        if name in ("status", "pull", "push", "backup-data"):
            sub.add_argument("--mirror", action="store_true", help="also remove destination-only files, keeping them in trash")
            sub.add_argument("--allow-empty", action="store_true", help="allow an intentionally empty mirror source")
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("Linux/WSL is required")
    os.umask(0o077)
    service = Service(args)
    if args.command == "install":
        service.install()
    elif args.command in ("enable-timer", "disable-timer"):
        service.timer()
    else:
        service.operate()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"Error: {error}")
