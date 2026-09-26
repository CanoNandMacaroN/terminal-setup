# Optional server storage and backup service

[Main README](../README_EN.md#server-services) · [中文](README.md)

A user-level module for shared storage, local working copies, snapshots, data backups, and optional scheduled runs. It does not mount disks, install system packages, or activate automatically with terminal setup.

## 1. Configure and install

Requires Linux/WSL, Python 3.11+, rsync, and accessible shared/local data storage. If terminal tools are missing, first run `./server-setup.sh --user-only` from the repository root.

```sh
cp -n server-services/config.example.toml "$HOME/server-services.toml"
```

Edit `~/server-services.toml` for the target machine:

| Setting | Value |
|---|---|
| `shared_mount` / `shared_root` | Existing shared mount point and your writable directory beneath it |
| `data_mount` / `data_root` | Existing local data mount point and your writable directory beneath it |
| `local_root` | Local working area, normally `~/local` |
| `links_root` | Shortcut directory, normally `~/storage` |
| `instance` | This server's backup name, such as `server-01`; use distinct names on different machines |

Paths support `~`, `$HOME`, and `$USER`, without evaluating shell code. The four functional roots must not overlap or pass through symlinks; they must belong to the current user and not be writable by others. Intermediate directories between the mount and personal root must not be writable by others. A mount point writable by multiple users needs the sticky bit and must belong to root or the current user. Mount checking prevents writes to underlying system-disk directories when storage is absent. Set `require_mounts = false` only for intentionally ordinary directories, such as a local test.

Preview and install:

```sh
./server-setup.sh --services --config "$HOME/server-services.toml" --dry-run
./server-setup.sh --services --config "$HOME/server-services.toml"
```

Alternatively use `./server-services/setup.sh --config "$HOME/server-services.toml"`. This entry installs only the storage module, without reinstalling the terminal baseline.

The installer creates directories and links, installs the independent `~/.local/bin/server-services` and `~/.local/bin/server-maintenance` commands, and saves configuration to `~/.config/terminal-setup/server-services.toml`. Existing real directories or links pointing elsewhere are not overwritten. No data is synchronized and no timer is enabled. Reinstalling from the repository updates both commands; replaced module files are backed up under `~/.local/state/terminal-setup/server-services/install-backups/`.

If PATH has not picked up the command, use `~/.local/bin/server-services` directly.

## 2. Storage layout

```text
~/local/
├── code/ tasks/    Local working copies; manually pull/push shared counterparts
└── scripts/ docs/          Locally authoritative; snapshot to shared storage

~/storage/                  Shortcut links only
├── code/ tasks/    → Shared master directories
├── backups/ env/ logs/     → Shared counterparts
├── dataset/               → Shared datasets, with backups under <instance>/input, output
└── data/
    ├── input/             → Local data disk: inputs
    ├── output/            → Local data disk: results
    └── scratch/           → Local data disk: temporary work, excluded from backups
```

Download and process large datasets on the local data disk, then back up results to shared storage. Keep shell configuration, package manifests, and credentials in the existing terminal/private-dotfiles workflow.

## 3. Daily commands

```sh
# Read-only projections in both directions
server-services status

# Before work: shared master → local copies
server-services pull --dry-run
server-services pull

# After work: local copies → shared master
server-services push --dry-run
server-services push

# Snapshot scripts/docs, retaining 10 completed versions by default
server-services snapshot

# Data input/output → shared dataset/<instance>/
server-services backup-data --dry-run
server-services backup-data
```

By default, synchronization adds and updates files, **without deleting destination-only files**. Overwritten versions go to `~/local/.sync-trash/` for pull, or shared `backups/server-services/<instance>/trash/` for push/data backup.

For intentional mirror deletions, preview first:

```sh
server-services push --mirror --dry-run
server-services push --mirror
```

Deleted files also go to trash. Empty mirror sources are rejected unless explicitly allowed with `--allow-empty`. Trash is not automatically pruned; review its storage usage periodically.

These commands perform directional rsync, not conflict merging. Pull before editing across machines, then push completed work; continue using Git for code. The shared lock serializes this module's writers, not editors or unrelated rsync processes.

## 4. Optional scheduled backup

```sh
server-services enable-timer --dry-run
server-services enable-timer
systemctl --user list-timers terminal-setup-backup.timer
journalctl --user -u terminal-setup-backup.service
server-services disable-timer
```

The timer runs `server-services backup` daily, snapshotting scripts/docs. Set `include_data = true` in the installed configuration to include input/output. After changing `calendar`, run `enable-timer` again. It never automatically pulls, pushes, or enables mirror deletion. Disabling the timer stops future triggers and preserves units and data.

Without a working `systemd --user`, run `server-services backup` manually or through an existing scheduler. Operation after logout depends on existing user-manager/linger policy; this module does not change system policy. `Persistent=true` catches up a missed trigger when the user manager resumes.

## 5. Move to another server or restore files

1. Obtain this repository, prepare terminal tools, and confirm the new machine's mounts.
2. Copy your configuration, adjust paths and `instance`, then repeat installation.
3. Preview and run `server-services pull`. Push completed work from the old machine first.
4. Previous scripts/docs are under shared `backups/server-services/<old instance>/snapshots/latest/`. Recover into a separate directory before merging, for example:

   ```sh
   rsync -a "$HOME/storage/backups/server-services/server-01/snapshots/latest/docs/" "$HOME/recovered-docs/"
   ```

Snapshots contain `scripts/` and `docs/` directly, without the old machine's absolute path. Unchanged files use hardlinks. Retention removes only completed, module-marked snapshots beyond the configured limit. Failed `.partial` directories never replace `latest`; inspect the error before removing them manually.

Existing shared code/tasks can be reused. Legacy dataset/input/output and old snapshots stay untouched; new data backups use per-instance destinations. Keep your own operational documents in local/docs and private material outside this public repository.

## 6. Troubleshooting

| Error | Resolution |
|---|---|
| `Storage is not mounted` | Check the real mount points and configuration; do not disable checks to hide an absent disk |
| Link location already contains data or another link | Inspect and move it yourself before reinstalling |
| `Storage is locked` | Inspect the shared-root lock for pull/push, or the lock under `backups/server-services/<instance>/` for snapshots/backups; remove a stale lock only after confirming its recorded process has stopped |
| Nonzero rsync result | Resolve permissions, quota, or network issues and retry; failures propagate to CLI/systemd |
| Unavailable `systemctl --user` | Use manual commands or an existing scheduler |

## 7. Codex / CodeBuddy runtime maintenance

These scripts also work independently, without configuring storage:

```sh
# Preview only by default
./server-services/maintenance.sh codex
./server-services/maintenance.sh codebuddy

# Fully exit the client and disconnect remote sessions before archiving
./server-services/maintenance.sh codex --apply
./server-services/maintenance.sh codebuddy --apply

# Include the listed history files/directories only when intended
./server-services/maintenance.sh codex --include-history --apply
```

After module installation, `~/.local/bin/server-maintenance` provides the same tool. It never stops processes. Archive and restore operations check for the current user's client processes and refuse while they are running.

| Client | Default archive scope | Added with `--include-history` |
|---|---|---|
| Codex | `log`, `cache`, `tmp`, `shell_snapshots` | `sessions`, `archived_sessions`, `history.jsonl`, `session_index.jsonl` |
| CodeBuddy | Server `data/logs` and top-level `.log` files | Editor history, workspace state, extension conversations/queue, and `expert-history.json` |

Configuration, credentials, plugins, databases, and worktrees stay untouched. **This is not a complete application reset**: database history indexes or desktop lists may remain. Use application-native controls to clear those.

Archives are stored inside each application's `.terminal-setup-archives/<timestamp>/`. The script prints the exact location. Exit the client before restoring and substitute that location below:

```sh
./server-services/maintenance.sh restore --archive /path/to/printed/archive
./server-services/maintenance.sh restore --archive /path/to/printed/archive --apply
```

Restore refuses to overwrite newly created runtime data; preserve and move it aside before retrying. The helper respects server-side `CODEX_HOME`, `CODEBUDDY_HOME`, and `CODEBUDDY_SERVER_HOME` overrides and rejects symlink paths. It does not manage macOS desktop state or uninstall toolchains.

Run the isolated tests:

```sh
python3 server-services/test_service.py
python3 server-services/test_maintenance.py
```

They use temporary storage, real rsync, and substitute process/service checks. They never archive the current account's client data or activate real services.
